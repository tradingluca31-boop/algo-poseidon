//+------------------------------------------------------------------+
//|                                   Zeus Forex Multi-Pairs EA      |
//|  Version: 1.0 - Multi-symboles Forex                             |
//|  H1 Signaux - H4 Filtres (RSI, SMMA200)                          |
//|  Max 3 trades/jour TOTAL - DD max 3% journalier                  |
//|  Risque 1% par trade - SL/TP 1% du capital                       |
//|  Paires: EUR/USD, GBP/USD, AUD/USD, NZD/USD, USD/CAD, USD/JPY, USD/CHF |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade Trade;

//======================== Inputs utilisateur ========================
input long     InpMagic                = 20250106;  // Magic Number unique

// --- Multi-symboles ---
string g_symbols[] = {"EURUSD", "GBPUSD", "AUDUSD", "NZDUSD", "USDCAD", "USDJPY", "USDCHF"};
int g_total_symbols = 7;

// --- 3 Signaux indépendants ---
input bool     InpUseEMA_Cross         = true;        // EMA21/55 croisement
input bool     InpUseMACD              = true;        // MACD histogramme
input bool     InpUseSMMA_Cross        = true;        // SMMA50/200 croisement H1
input int      InpMinSignalsRequired   = 2;           // Signaux minimum requis (1, 2 ou 3)

// --- MACD SMA config ---
input int      InpMACD_Fast            = 20;          // SMA rapide
input int      InpMACD_Slow            = 35;          // SMA lente
input int      InpMACD_Signal          = 15;          // SMA du MACD

// --- Risque / gestion (en %) ---
input double InpRiskPercent        = 1.0;   // % de la BALANCE risqué par trade
input double InpSL_PercentOfCapital = 1.0;  // SL = 1% du capital
input double InpTP_PercentOfCapital = 1.0;  // TP = 1% du capital

input int    InpMaxTradesPerDay    = 3;     // Max 3 trades/jour TOTAL
input double InpMaxDailyDD_Percent = 3.0;   // DD max journalier (pertes réalisées)

// --- Fenêtre d'ouverture ---
input ENUM_TIMEFRAMES InpSignalTF      = PERIOD_H1;   // TF signaux (H1)
input int      InpSessionStartHour     = 6;           // Ouverture 6h (heure serveur)
input int      InpSessionEndHour       = 15;          // Fermeture 15h
input int      InpSlippagePoints       = 20;
input bool     InpVerboseLogs          = false;

// --- SMMA50 + Score conditions ---
input bool InpUseSMMA50Trend    = true;             // Filtre tendance SMMA50
input int  InpSMMA_Period       = 50;               // Période SMMA
input ENUM_TIMEFRAMES InpSMMA_TF = PERIOD_H4;       // UT SMMA (H4)

// --- RSI Filter ---
input bool InpUseRSI = true;                                // Utiliser filtre RSI
input ENUM_TIMEFRAMES InpRSITF = PERIOD_H4;                 // TimeFrame RSI (H4)
input int InpRSIPeriod = 14;                                // Période RSI
input int InpRSIOverbought = 70;                            // Seuil surachat RSI
input int InpRSIOversold = 25;                              // Seuil survente RSI
input bool InpRSIBlockEqual = true;                         // Bloquer si == aux seuils

// --- Break Even ---
input double InpBE_TriggerPercent  = 1.0;  // Passer BE quand +1% depuis l'entrée

//======================== Variables Globales ========================
datetime lastBarTime[];
int tradedDay=-1, tradesCountToday=0;
double dailyRealizedPL = 0.0;  // Profit/Loss réalisé du jour
datetime lastResetDate = 0;

// Handles des indicateurs pour chaque symbole
int hEMA21[], hEMA55[];
int hSMAfast[], hSMAslow[];
int hSMMA50[], hSMMA50_Signal[], hSMMA200_Signal[];
int hRSI[];

// RSI cache par symbole
double rsi_val[];
datetime rsi_last_bar_time[];

//======================== Utils Temps ======================
bool IsNewBar(int symIdx)
{
   datetime ct = iTime(g_symbols[symIdx], InpSignalTF, 0);
   if(ct != lastBarTime[symIdx])
   {
      lastBarTime[symIdx] = ct;
      return true;
   }
   return false;
}

void ResetDayIfNeeded()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   if(tradedDay != t.day_of_year)
   {
      tradedDay = t.day_of_year;
      tradesCountToday = 0;
      dailyRealizedPL = 0.0;

      if(InpVerboseLogs)
         PrintFormat("[RESET DAY] Nouveau jour: %d, Trades=%d, DD=%.2f",
                     t.day_of_year, tradesCountToday, dailyRealizedPL);
   }
}

bool CanOpenToday()
{
   ResetDayIfNeeded();
   return tradesCountToday < InpMaxTradesPerDay;
}

void MarkTradeOpened()
{
   ResetDayIfNeeded();
   tradesCountToday++;

   if(InpVerboseLogs)
      PrintFormat("[TRADE OPENED] Total aujourd'hui: %d/%d", tradesCountToday, InpMaxTradesPerDay);
}

bool InEntryWindow()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   if(InpSessionStartHour <= InpSessionEndHour)
      return (t.hour >= InpSessionStartHour && t.hour < InpSessionEndHour);

   return (t.hour >= InpSessionStartHour || t.hour < InpSessionEndHour);
}

// Vérifie si le DD journalier réalisé dépasse 3%
bool IsDailyDDExceeded()
{
   ResetDayIfNeeded();

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return false;

   double ddPercent = (dailyRealizedPL / balance) * 100.0;

   if(ddPercent <= -InpMaxDailyDD_Percent)
   {
      if(InpVerboseLogs)
         PrintFormat("[DD EXCEEDED] DD journalier: %.2f%% (limite: %.2f%%) - Pas de nouvelle position",
                     ddPercent, InpMaxDailyDD_Percent);
      return true;
   }

   return false;
}

// Met à jour le DD journalier en parcourant les deals fermés aujourd'hui
void UpdateDailyRealizedPL()
{
   ResetDayIfNeeded();

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);

   datetime startOfDay = StructToTime(t);
   startOfDay -= t.hour * 3600 + t.min * 60 + t.sec; // Minuit

   HistorySelect(startOfDay, TimeCurrent());

   double totalPL = 0.0;
   int totalDeals = HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagic) continue;
      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      totalPL += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      totalPL += HistoryDealGetDouble(ticket, DEAL_SWAP);
      totalPL += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }

   dailyRealizedPL = totalPL;
}

//======================== Indicateurs ======================
bool GetEMAs(int symIdx, double &e21_1, double &e55_1, double &e21_2, double &e55_2)
{
   double b21[], b55[];
   ArraySetAsSeries(b21, true);
   ArraySetAsSeries(b55, true);

   if(CopyBuffer(hEMA21[symIdx], 0, 1, 2, b21) < 2) return false;
   if(CopyBuffer(hEMA55[symIdx], 0, 1, 2, b55) < 2) return false;

   e21_1 = b21[0]; e21_2 = b21[1];
   e55_1 = b55[0]; e55_2 = b55[1];

   return true;
}

bool GetMACD_SMA(int symIdx, double &macd_1, double &sig_1, double &macd_2, double &sig_2)
{
   int need = MathMax(MathMax(InpMACD_Fast, InpMACD_Slow), InpMACD_Signal) + 5;
   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(hSMAfast[symIdx], 0, 1, need, fast) < need) return false;
   if(CopyBuffer(hSMAslow[symIdx], 0, 1, need, slow) < need) return false;

   double macdArr[];
   ArrayResize(macdArr, need);
   for(int i = 0; i < need; i++) macdArr[i] = fast[i] - slow[i];

   double sigArr[];
   ArrayResize(sigArr, need);
   int p = InpMACD_Signal;
   double acc = 0;

   for(int i = 0; i < need; i++)
   {
      acc += macdArr[i];
      if(i >= p) acc -= macdArr[i - p];
      if(i >= p - 1) sigArr[i] = acc / p;
      else sigArr[i] = macdArr[i];
   }

   macd_1 = macdArr[0];
   sig_1 = sigArr[0];
   macd_2 = macdArr[1];
   sig_2 = sigArr[1];

   return true;
}

//------------------------ Signaux ----------------------
bool GetSMMA50(int symIdx, double &out_smma)
{
   if(!InpUseSMMA50Trend) return false;
   if(hSMMA50[symIdx] == INVALID_HANDLE) return false;

   double b[];
   ArraySetAsSeries(b, true);

   if(CopyBuffer(hSMMA50[symIdx], 0, 0, 1, b) < 1) return false;

   out_smma = b[0];
   return true;
}

int TrendDir_SMMA50(int symIdx)
{
   if(!InpUseSMMA50Trend) return 0;

   double smma = 0.0;
   if(!GetSMMA50(symIdx, smma)) return 0;

   string sym = g_symbols[symIdx];
   double bid = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double px = (bid + ask) * 0.5;

   if(px > smma) return +1;
   if(px < smma) return -1;
   return 0;
}

bool GetEMACrossSignal(int symIdx, bool &buy, bool &sell)
{
   buy = false; sell = false;
   double e21_1, e55_1, e21_2, e55_2;

   if(!GetEMAs(symIdx, e21_1, e55_1, e21_2, e55_2)) return false;

   buy = (e21_2 <= e55_2 && e21_1 > e55_1);
   sell = (e21_2 >= e55_2 && e21_1 < e55_1);

   return true;
}

bool GetMACD_HistSignal(int symIdx, bool &buy, bool &sell)
{
   buy = false; sell = false;
   double m1, s1, m2, s2;

   if(!GetMACD_SMA(symIdx, m1, s1, m2, s2)) return false;

   double hist = (m1 - s1);
   buy = (hist > 0.0);
   sell = (hist < 0.0);

   return true;
}

bool GetSMMA50_DirectionH1(int symIdx, bool &buy, bool &sell)
{
   buy = false; sell = false;
   if(!InpUseSMMA_Cross) return false;

   double smma50[], smma200[];
   ArraySetAsSeries(smma50, true);
   ArraySetAsSeries(smma200, true);

   if(CopyBuffer(hSMMA50_Signal[symIdx], 0, 0, 2, smma50) < 2) return false;
   if(CopyBuffer(hSMMA200_Signal[symIdx], 0, 0, 2, smma200) < 2) return false;

   buy = (smma50[0] > smma200[0]);
   sell = (smma50[0] < smma200[0]);

   return true;
}

//======================== Filtres ======================
bool IsRSIFilterOK(int symIdx)
{
   if(!InpUseRSI) return true;

   string sym = g_symbols[symIdx];
   datetime current_bar = iTime(sym, InpRSITF, 0);

   if(rsi_last_bar_time[symIdx] == current_bar && rsi_val[symIdx] != EMPTY_VALUE)
      return CheckRSILevel(rsi_val[symIdx]);

   double rsi_buffer[];
   ArraySetAsSeries(rsi_buffer, true);

   if(CopyBuffer(hRSI[symIdx], 0, 1, 1, rsi_buffer) < 1)
   {
      if(InpVerboseLogs) PrintFormat("[RSI] %s - Erreur lecture buffer", sym);
      return false;
   }

   rsi_val[symIdx] = rsi_buffer[0];
   rsi_last_bar_time[symIdx] = current_bar;

   return CheckRSILevel(rsi_val[symIdx]);
}

bool CheckRSILevel(double rsi)
{
   if(InpRSIBlockEqual)
   {
      if(rsi >= InpRSIOverbought || rsi <= InpRSIOversold)
      {
         if(InpVerboseLogs)
            PrintFormat("[RSI] Bloqué: RSI=%.2f (seuils: %d/%d)",
                        rsi, InpRSIOversold, InpRSIOverbought);
         return false;
      }
   }
   else
   {
      if(rsi > InpRSIOverbought || rsi < InpRSIOversold)
      {
         if(InpVerboseLogs)
            PrintFormat("[RSI] Bloqué: RSI=%.2f (seuils: %d/%d)",
                        rsi, InpRSIOversold, InpRSIOverbought);
         return false;
      }
   }

   return true;
}

//======================== Calcul SL/TP basé sur % Capital ========================
void CalculateSL_TP_FromCapital(string sym, int dir, double entry, double lots, double &sl, double &tp)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double targetLoss = balance * (InpSL_PercentOfCapital / 100.0);
   double targetProfit = balance * (InpTP_PercentOfCapital / 100.0);

   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0 || lots <= 0)
   {
      // Fallback: 1% du prix
      if(dir > 0)
      {
         sl = entry * 0.99;
         tp = entry * 1.01;
      }
      else
      {
         sl = entry * 1.01;
         tp = entry * 0.99;
      }

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
      return;
   }

   // Calcul distance SL pour atteindre la perte cible
   double distanceSL = (targetLoss * tickSize) / (tickValue * lots);

   // Calcul distance TP pour atteindre le profit cible
   double distanceTP = (targetProfit * tickSize) / (tickValue * lots);

   if(dir > 0) // BUY
   {
      sl = entry - distanceSL;
      tp = entry + distanceTP;
   }
   else // SELL
   {
      sl = entry + distanceSL;
      tp = entry - distanceTP;
   }

   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   if(InpVerboseLogs)
      PrintFormat("[SL/TP] %s - Balance=%.2f, Entry=%.5f, SL=%.5f (%.2f$), TP=%.5f (%.2f$)",
                  sym, balance, entry, sl, targetLoss, tp, targetProfit);
}

//======================== Sizing 1% FIXE ===================
double LossPerLotAtSL(string sym, int dir, double entry, double sl)
{
   double p = 0.0;
   bool ok = (dir > 0) ? OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, entry, sl, p)
                       : OrderCalcProfit(ORDER_TYPE_SELL, sym, 1.0, entry, sl, p);

   if(ok) return MathAbs(p);

   double tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double dist = MathAbs(entry - sl);

   if(tv > 0 && ts > 0) return (dist / ts) * tv;

   return 0.0;
}

double LotsFromRisk(string sym, int dir, double entry, double slTemp)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

   double lossPerLot = LossPerLotAtSL(sym, dir, entry, slTemp);
   if(lossPerLot <= 0) return 0.0;

   double lots = riskMoney / lossPerLot;

   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

   if(step <= 0) step = 0.01;

   lots = MathFloor(lots / step) * step;
   lots = MathMax(minL, MathMin(lots, maxL));

   if(InpVerboseLogs)
      PrintFormat("[Sizing] %s - Balance=%.2f, Risk$=%.2f, Entry=%.5f, SL=%.5f, LossPerLot=%.2f, Lots=%.2f",
                  sym, balance, riskMoney, entry, slTemp, lossPerLot, lots);

   return lots;
}

//======================== Ouverture ========================
void TryOpenTrade(int symIdx)
{
   if(!InEntryWindow()) return;
   if(!CanOpenToday()) return;
   if(IsDailyDDExceeded()) return; // Bloque si DD >= 3%

   if(!IsRSIFilterOK(symIdx)) return;

   int scoreBuy = 0, scoreSell = 0;

   // SIGNAL 1: EMA21/55
   bool emaB = false, emaS = false;
   if(InpUseEMA_Cross)
   {
      GetEMACrossSignal(symIdx, emaB, emaS);
      if(emaB) scoreBuy++;
      if(emaS) scoreSell++;
   }

   // SIGNAL 2: MACD histogramme
   bool macdB = false, macdS = false;
   if(InpUseMACD)
   {
      GetMACD_HistSignal(symIdx, macdB, macdS);
      if(macdB) scoreBuy++;
      if(macdS) scoreSell++;
   }

   // SIGNAL 3: SMMA50/200 H1
   bool smmaB = false, smmaS = false;
   if(InpUseSMMA_Cross)
   {
      GetSMMA50_DirectionH1(symIdx, smmaB, smmaS);
      if(smmaB) scoreBuy++;
      if(smmaS) scoreSell++;
   }

   // FILTRE SMMA50 H4
   int tdir = TrendDir_SMMA50(symIdx);
   bool allowBuy = (!InpUseSMMA50Trend || tdir > 0);
   bool allowSell = (!InpUseSMMA50Trend || tdir < 0);

   int dir = 0;
   if(scoreBuy >= InpMinSignalsRequired && allowBuy) dir = +1;
   if(scoreSell >= InpMinSignalsRequired && allowSell && dir == 0) dir = -1;

   if(dir == 0) return;

   string sym = g_symbols[symIdx];
   double entry = (dir > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);

   // Calcul temporaire du SL pour dimensionner les lots (1% du prix pour estimation)
   int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   double slTemp = (dir > 0) ? entry * 0.99 : entry * 1.01;
   slTemp = NormalizeDouble(slTemp, digits);

   double lots = LotsFromRisk(sym, dir, entry, slTemp);
   if(lots <= 0) return;

   // Calcul FINAL du SL/TP basé sur 1% du capital
   double sl, tp;
   CalculateSL_TP_FromCapital(sym, dir, entry, lots, sl, tp);

   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpSlippagePoints);

   string cmt = StringFormat("Zeus_%s", sym);
   bool ok = (dir > 0) ? Trade.Buy(lots, sym, entry, sl, tp, cmt)
                       : Trade.Sell(lots, sym, entry, sl, tp, cmt);

   if(ok)
   {
      MarkTradeOpened();
      PrintFormat("[TRADE OPENED] %s %s %.2f lots @ %.5f | SL=%.5f TP=%.5f",
                  (dir > 0 ? "BUY" : "SELL"), sym, lots, entry, sl, tp);
   }
}

//======================== Gestion BE =======================
void ManageBreakEven(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      long type = (long)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double price = (type == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(sym, SYMBOL_BID)
                     : SymbolInfoDouble(sym, SYMBOL_ASK);

      double beTrigger = (type == POSITION_TYPE_BUY)
                         ? entry * (1.0 + InpBE_TriggerPercent / 100.0)
                         : entry * (1.0 - InpBE_TriggerPercent / 100.0);

      bool condPercent = (type == POSITION_TYPE_BUY) ? (price >= beTrigger) : (price <= beTrigger);

      if(condPercent)
      {
         int d = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         double point = SymbolInfoDouble(sym, SYMBOL_POINT);
         double targetSL = NormalizeDouble(entry, d);

         bool need = (type == POSITION_TYPE_BUY) ? (sl < targetSL - 10 * point)
                                                 : (sl > targetSL + 10 * point);

         if(need)
         {
            Trade.PositionModify(sym, targetSL, tp);
            PrintFormat("[BE] %s - Entry=%.5f, Price=%.5f, SL->%.5f", sym, entry, price, targetSL);
         }
      }
   }
}

//======================== OnTick ==========================
void OnTick()
{
   // Mise à jour du DD journalier
   UpdateDailyRealizedPL();

   // Gestion Break Even pour toutes les positions
   for(int i = 0; i < g_total_symbols; i++)
   {
      ManageBreakEven(g_symbols[i]);
   }

   // Scan des signaux sur toutes les paires
   for(int i = 0; i < g_total_symbols; i++)
   {
      if(IsNewBar(i))
      {
         TryOpenTrade(i);
      }
   }
}

//======================== Events ==========================
int OnInit()
{
   Print("=== Zeus Forex Multi-Pairs EA - Initialisation ===");

   // Resize arrays
   ArrayResize(lastBarTime, g_total_symbols);
   ArrayResize(hEMA21, g_total_symbols);
   ArrayResize(hEMA55, g_total_symbols);
   ArrayResize(hSMAfast, g_total_symbols);
   ArrayResize(hSMAslow, g_total_symbols);
   ArrayResize(hSMMA50, g_total_symbols);
   ArrayResize(hSMMA50_Signal, g_total_symbols);
   ArrayResize(hSMMA200_Signal, g_total_symbols);
   ArrayResize(hRSI, g_total_symbols);
   ArrayResize(rsi_val, g_total_symbols);
   ArrayResize(rsi_last_bar_time, g_total_symbols);

   // Initialize handles for all symbols
   for(int i = 0; i < g_total_symbols; i++)
   {
      string sym = g_symbols[i];

      lastBarTime[i] = 0;
      rsi_val[i] = EMPTY_VALUE;
      rsi_last_bar_time[i] = 0;

      hEMA21[i] = iMA(sym, InpSignalTF, 21, 0, MODE_EMA, PRICE_CLOSE);
      hEMA55[i] = iMA(sym, InpSignalTF, 55, 0, MODE_EMA, PRICE_CLOSE);
      hSMAfast[i] = iMA(sym, InpSignalTF, InpMACD_Fast, 0, MODE_SMA, PRICE_CLOSE);
      hSMAslow[i] = iMA(sym, InpSignalTF, InpMACD_Slow, 0, MODE_SMA, PRICE_CLOSE);

      if(InpUseSMMA50Trend)
         hSMMA50[i] = iMA(sym, InpSMMA_TF, InpSMMA_Period, 0, MODE_SMMA, PRICE_CLOSE);

      if(InpUseSMMA_Cross)
      {
         hSMMA50_Signal[i] = iMA(sym, PERIOD_H1, 50, 0, MODE_SMMA, PRICE_CLOSE);
         hSMMA200_Signal[i] = iMA(sym, PERIOD_H1, 200, 0, MODE_SMMA, PRICE_CLOSE);
      }

      if(InpUseRSI)
      {
         hRSI[i] = iRSI(sym, InpRSITF, InpRSIPeriod, PRICE_CLOSE);
         if(hRSI[i] == INVALID_HANDLE)
         {
            PrintFormat("ERREUR: RSI init failed pour %s", sym);
            return INIT_FAILED;
         }
      }

      if(hEMA21[i] == INVALID_HANDLE || hEMA55[i] == INVALID_HANDLE ||
         hSMAfast[i] == INVALID_HANDLE || hSMAslow[i] == INVALID_HANDLE ||
         (InpUseSMMA50Trend && hSMMA50[i] == INVALID_HANDLE) ||
         (InpUseSMMA_Cross && (hSMMA50_Signal[i] == INVALID_HANDLE || hSMMA200_Signal[i] == INVALID_HANDLE)))
      {
         PrintFormat("ERREUR: Handle indicateur invalide pour %s", sym);
         return INIT_FAILED;
      }

      PrintFormat("✅ Indicateurs initialisés pour %s", sym);
   }

   PrintFormat("✅ EA prêt - %d paires surveillées - Max %d trades/jour - DD max %.2f%%",
               g_total_symbols, InpMaxTradesPerDay, InpMaxDailyDD_Percent);

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Print("=== Zeus Forex Multi-Pairs EA - Deinitialisation ===");

   for(int i = 0; i < g_total_symbols; i++)
   {
      if(hEMA21[i] != INVALID_HANDLE) IndicatorRelease(hEMA21[i]);
      if(hEMA55[i] != INVALID_HANDLE) IndicatorRelease(hEMA55[i]);
      if(hSMAfast[i] != INVALID_HANDLE) IndicatorRelease(hSMAfast[i]);
      if(hSMAslow[i] != INVALID_HANDLE) IndicatorRelease(hSMAslow[i]);
      if(hSMMA50[i] != INVALID_HANDLE) IndicatorRelease(hSMMA50[i]);
      if(hSMMA50_Signal[i] != INVALID_HANDLE) IndicatorRelease(hSMMA50_Signal[i]);
      if(hSMMA200_Signal[i] != INVALID_HANDLE) IndicatorRelease(hSMMA200_Signal[i]);
      if(hRSI[i] != INVALID_HANDLE) IndicatorRelease(hRSI[i]);
   }

   Print("✅ Tous les handles libérés");
}
