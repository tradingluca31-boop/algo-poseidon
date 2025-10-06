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

// [ADDED] Option A — réduction du risque après série de pertes
input bool   UseLossStreakReduction = true;   // ON/OFF
input int    LossStreakTrigger      = 7;      // Value=7 / Start=3 / Step=1 / Stop=15
input double LossStreakFactor       = 0.50;   // Value=0.50 / Start=0.20 / Step=0.10 / Stop=1.00

// [ADDED] Option A — RISQUE EN MONTANT FIXE (devise du compte)
input bool   UseFixedRiskMoney = true;   // Utiliser un montant fixe (€) au lieu du %
input double FixedRiskMoney     = 100.0; // Montant risqué par trade (ex: 100€)
input double ReducedRiskMoney   = 50.0;  // Montant risqué sous série de pertes (ex: 50€)

input double InpSL_PercentOfCapital = 1.0;  // SL = 1% du capital
input double InpTP_PercentOfCapital = 1.0;  // TP = 1% du capital
input double InpBE_TriggerPercent  = 1.0;   // Passer BE quand +1% depuis l'entrée
input int    InpTimeStop_Hours     = 72;    // Fermeture auto après X heures (Value=72 / Start=12 / Step=12 / Stop=168)

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

// --- Sentiment Retail Filter ---
input bool InpUseSentimentFilter = true;                        // Utiliser filtre Sentiment Retail Myfxbook
input double InpSentimentThreshold = 80.0;                      // Seuil bloquant (>80% = bloque même sens)

//=== Month Filter Inputs START ===========================================
input bool InpTrade_Janvier   = true;  // Trader en Janvier
input bool InpTrade_Fevrier   = true;  // Trader en Fevrier
input bool InpTrade_Mars      = false; // Trader en Mars
input bool InpTrade_Avril     = true;  // Trader en Avril
input bool InpTrade_Mai       = true;  // Trader en Mai
input bool InpTrade_Juin      = true;  // Trader en Juin
input bool InpTrade_Juillet   = true;  // Trader en Juillet
input bool InpTrade_Aout      = true;  // Trader en Aout
input bool InpTrade_Septembre = true;  // Trader en Septembre
input bool InpTrade_Octobre   = true;  // Trader en Octobre
input bool InpTrade_Novembre  = true;  // Trader en Novembre
input bool InpTrade_Decembre  = true;  // Trader en Decembre
//=== Month Filter Inputs END =============================================

//======================== Variables Globales ========================
datetime lastBarTime[];
int tradedDay=-1, tradesCountToday=0;
double dailyRealizedPL = 0.0;  // Profit/Loss réalisé du jour
datetime lastResetDate = 0;
int gLossStreak = 0;   // [ADDED] Compteur pertes consécutives

// Handles des indicateurs pour chaque symbole
int hEMA21[], hEMA55[];
int hSMAfast[], hSMAslow[];
int hSMMA50[], hSMMA50_Signal[], hSMMA200_Signal[];
int hRSI[];

// RSI cache par symbole
double rsi_val[];
datetime rsi_last_bar_time[];

// [ADDED] Sentiment Retail variables
double sentiment_long_pct = EMPTY_VALUE;
double sentiment_short_pct = EMPTY_VALUE;
datetime sentiment_last_update = 0;

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

   // [CHANGED] Poseidon Option A — risque en € fixe + réduction série
   double riskMoney = balance * (InpRiskPercent / 100.0); // fallback %

   if(UseFixedRiskMoney)
      riskMoney = FixedRiskMoney;

   if(UseLossStreakReduction)
   {
      gLossStreak = CountConsecutiveLosses();
      if(gLossStreak >= LossStreakTrigger)
      {
         if(UseFixedRiskMoney) riskMoney = ReducedRiskMoney;
         else                  riskMoney *= LossStreakFactor;
      }
      if(InpVerboseLogs) PrintFormat("[LossStreak] count=%d, riskMoney=%.2f", gLossStreak, riskMoney);
   }

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
   // [ADDED] Month Filter Guard
   if(!IsTradingMonth(TimeCurrent())) return;

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

   // [ADDED] Filtre Sentiment Retail - vérifie la direction choisie
   if(!IsSentimentFilterOK(dir)) return;

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

   string cmt = "BASE";
   if(UseLossStreakReduction && gLossStreak >= LossStreakTrigger) cmt = "RISK-REDUCED";

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

//======================== Gestion Time Stop =======================
void ManageTimeStop(string sym)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      datetime currentTime = TimeCurrent();

      int elapsedHours = (int)((currentTime - openTime) / 3600);

      if(elapsedHours >= InpTimeStop_Hours)
      {
         Trade.PositionClose(ticket);
         PrintFormat("[TIME STOP] %s - Position fermée après %d heures (limite: %d h)",
                     sym, elapsedHours, InpTimeStop_Hours);
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

   // Gestion Time Stop pour toutes les positions
   for(int i = 0; i < g_total_symbols; i++)
   {
      ManageTimeStop(g_symbols[i]);
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
   Print("🛑 === OnDeinit appelé - Raison: ", reason, " ===");

   // BACKUP: Export aussi dans OnDeinit au cas où OnTesterDeinit ne marche pas
   if(MQLInfoInteger(MQL_TESTER))
   {
      Print("🚀 OnDeinit: Mode testeur détecté - Lancement export de sauvegarde");
      ExportTradeHistoryCSV();
   }

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

   Print("✅ OnDeinit: Handles libérés");
}

//======================== [ADDED] Functions for LossStreak ========================
int CountConsecutiveLosses()
{
   int count = 0;
   datetime endTime = TimeCurrent();
   datetime startTime = endTime - 86400 * 30; // 30 derniers jours

   HistorySelect(startTime, endTime);
   int totalDeals = HistoryDealsTotal();

   // Parcourir les deals du plus récent au plus ancien
   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic)
      {
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if(profit < 0) count++;
         else break; // Arrêter au premier trade gagnant
      }
   }

   return count;
}

//======================== [ADDED] Month Filter Functions ========================
bool IsTradingMonth(datetime currentTime)
{
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);

   switch(dt.mon)
   {
      case  1: return InpTrade_Janvier;
      case  2: return InpTrade_Fevrier;
      case  3: return InpTrade_Mars;
      case  4: return InpTrade_Avril;
      case  5: return InpTrade_Mai;
      case  6: return InpTrade_Juin;
      case  7: return InpTrade_Juillet;
      case  8: return InpTrade_Aout;
      case  9: return InpTrade_Septembre;
      case 10: return InpTrade_Octobre;
      case 11: return InpTrade_Novembre;
      case 12: return InpTrade_Decembre;
      default: return false;
   }
}

string MonthToString(int month)
{
   switch(month)
   {
      case  1: return "Janvier";
      case  2: return "Fevrier";
      case  3: return "Mars";
      case  4: return "Avril";
      case  5: return "Mai";
      case  6: return "Juin";
      case  7: return "Juillet";
      case  8: return "Aout";
      case  9: return "Septembre";
      case 10: return "Octobre";
      case 11: return "Novembre";
      case 12: return "Decembre";
      default: return "Inconnu";
   }
}

//======================== [ADDED] Sentiment Retail Filter Functions ========================
bool UpdateSentimentData()
{
   if(!InpUseSentimentFilter) return true;

   // Eviter les appels trop frequents (maximum 1 fois par jour en backtest)
   datetime currentTime = TimeCurrent();
   if(sentiment_last_update > 0 && (currentTime - sentiment_last_update) < 86400)
   {
      return true; // Utiliser les donnees en cache
   }

   // MODE BACKTEST: Simuler sentiment retail realiste CONTRARIAN (retail perd)
   if(MQLInfoInteger(MQL_TESTER))
   {
      // Utiliser le prix actuel pour determiner le sentiment
      double close_h1 = iClose(_Symbol, PERIOD_H1, 1);
      double close_h1_prev = iClose(_Symbol, PERIOD_H1, 10);

      // RETAIL = CONTRARIAN: Si prix monte, retail VEND (pense que c'est trop cher)
      // Si prix baisse, retail ACHETE (pense que c'est bon marche)
      if(close_h1 > close_h1_prev)
      {
         // Prix monte -> Retail vend massivement (pense "c'est le top")
         sentiment_short_pct = 55.0 + (MathRand() % 30); // 55-85% Short
         sentiment_long_pct = 100.0 - sentiment_short_pct;
      }
      else
      {
         // Prix baisse -> Retail achete massivement (pense "c'est le creux")
         sentiment_long_pct = 55.0 + (MathRand() % 30); // 55-85% Long
         sentiment_short_pct = 100.0 - sentiment_long_pct;
      }

      sentiment_last_update = currentTime;

      PrintFormat("[Sentiment] BACKTEST CONTRARIAN - Long: %.1f%%, Short: %.1f%%",
                  sentiment_long_pct, sentiment_short_pct);
      return true;
   }

   // MODE LIVE: Preparer la requete WebRequest vers Myfxbook
   string url = "https://www.myfxbook.com/community/outlook/" + _Symbol;
   string cookie = NULL, headers;
   char post[], result[];

   // Tentative de recuperation des donnees reelles
   ResetLastError();
   int timeout = 5000; // 5 secondes
   int res = WebRequest("GET", url, cookie, NULL, timeout, post, 0, result, headers);

   if(res == 200 && ArraySize(result) > 0)
   {
      // Convertir le resultat en string
      string html = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);

      // Parser le HTML pour extraire les pourcentages Long/Short
      int pos_long = StringFind(html, "longPercentage");
      int pos_short = StringFind(html, "shortPercentage");

      if(pos_long > 0 && pos_short > 0)
      {
         // Extraire le pourcentage Long
         int start_long = StringFind(html, ">", pos_long) + 1;
         int end_long = StringFind(html, "%", start_long);
         string long_str = StringSubstr(html, start_long, end_long - start_long);
         StringTrimLeft(long_str);
         StringTrimRight(long_str);
         sentiment_long_pct = StringToDouble(long_str);

         // Extraire le pourcentage Short
         int start_short = StringFind(html, ">", pos_short) + 1;
         int end_short = StringFind(html, "%", start_short);
         string short_str = StringSubstr(html, start_short, end_short - start_short);
         StringTrimLeft(short_str);
         StringTrimRight(short_str);
         sentiment_short_pct = StringToDouble(short_str);

         sentiment_last_update = currentTime;

         PrintFormat("[Sentiment] REEL Myfxbook - Long: %.1f%%, Short: %.1f%%",
                     sentiment_long_pct, sentiment_short_pct);
         return true;
      }
   }

   // Fallback LIVE: si WebRequest echoue, utiliser des valeurs neutres
   int error = GetLastError();
   PrintFormat("[Sentiment] ERREUR WebRequest (%d) - Utilisation valeurs neutres 50/50", error);

   sentiment_long_pct = 50.0;
   sentiment_short_pct = 50.0;
   sentiment_last_update = currentTime;

   return true;
}

bool IsSentimentFilterOK(int direction)
{
   if(!InpUseSentimentFilter) return true;

   if(!UpdateSentimentData())
   {
      if(InpVerboseLogs) Print("[Sentiment] Erreur récupération données - Autorise trading");
      return true; // En cas d'erreur, on laisse passer
   }

   // Zone neutre 50-70% : aucune majorité forte
   if(sentiment_long_pct <= InpSentimentThreshold && sentiment_short_pct <= InpSentimentThreshold)
   {
      if(InpVerboseLogs) PrintFormat("[Sentiment] Zone neutre - Long: %.1f%%, Short: %.1f%% - OK",
                                    sentiment_long_pct, sentiment_short_pct);
      return true;
   }

   // Si > seuil : on bloque le sens majoritaire
   if(direction > 0)   // BUY
   {
      if(sentiment_long_pct > InpSentimentThreshold)
      {
         if(InpVerboseLogs) PrintFormat("[Sentiment] BLOQUÉ BUY - Long majoritaire: %.1f%% (>%.1f%%)",
                                       sentiment_long_pct, InpSentimentThreshold);
         return false;
      }
   }

   if(direction < 0)   // SELL
   {
      if(sentiment_short_pct > InpSentimentThreshold)
      {
         if(InpVerboseLogs) PrintFormat("[Sentiment] BLOQUÉ SELL - Short majoritaire: %.1f%% (>%.1f%%)",
                                       sentiment_short_pct, InpSentimentThreshold);
         return false;
      }
   }

   return true;
}

//======================== [ADDED] Export CSV Functions ========================
void ExportTradeHistoryCSV()
{
   Print("=== DÉBUT EXPORT CSV TRADES - MULTI-PAIRS ===");

   string file_name = "ZEUS_FOREX_MULTI_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";

   // Priorité 1: FILE_COMMON (accessible dans MQL5/Files/Common/)
   int file_handle = FileOpen(file_name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, 0, CP_UTF8);
   if(file_handle == INVALID_HANDLE)
   {
      Print("Échec FILE_COMMON, essai sans FILE_COMMON");
      // Priorité 2: Sans FILE_COMMON (Tester/Files/)
      file_handle = FileOpen(file_name, FILE_WRITE | FILE_CSV | FILE_ANSI, 0, CP_UTF8);
   }

   if(file_handle == INVALID_HANDLE)
   {
      Print("ERREUR CRITIQUE: Impossible de créer le fichier CSV. Erreur: ", GetLastError());
      return;
   }

   Print("✅ Fichier CSV ouvert avec succès: ", file_name);

   // En-têtes CSV
   FileWrite(file_handle, "magic,symbol,type,time_open,time_close,price_open,price_close,profit,volume,swap,commission,comment");

   datetime startDate = D'2020.01.01';
   datetime endDate = TimeCurrent() + 86400;

   if(HistorySelect(startDate, endDate))
   {
      Print("✅ Historique sélectionné avec succès");
      int total_deals = HistoryDealsTotal();
      Print("📊 Nombre total de deals: ", total_deals);

      int exported_count = 0;

      for(int i = 0; i < total_deals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;

         long deal_magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(deal_magic != InpMagic) continue; // Filtrer par magic number

         // Exporter seulement les deals de sortie (fermeture de position)
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            string deal_symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
            long deal_time = HistoryDealGetInteger(ticket, DEAL_TIME);
            double deal_price = HistoryDealGetDouble(ticket, DEAL_PRICE);
            double deal_profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            double deal_volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            double deal_swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
            double deal_commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            string deal_comment = HistoryDealGetString(ticket, DEAL_COMMENT);

            // Formatage CSV avec toutes les données importantes
            string csv_line = IntegerToString(deal_magic) + "," +
                             deal_symbol + "," +
                             IntegerToString(deal_type) + "," +
                             IntegerToString(deal_time) + "," +
                             IntegerToString(deal_time) + "," +
                             DoubleToString(deal_price, 5) + "," +
                             DoubleToString(deal_price, 5) + "," +
                             DoubleToString(deal_profit, 2) + "," +
                             DoubleToString(deal_volume, 2) + "," +
                             DoubleToString(deal_swap, 2) + "," +
                             DoubleToString(deal_commission, 2) + "," +
                             deal_comment;

            FileWrite(file_handle, csv_line);
            exported_count++;
         }
      }

      Print("🎯 Nombre de trades exportés: ", exported_count);
   }
   else
   {
      Print("❌ ERREUR: Impossible de sélectionner l'historique. Erreur: ", GetLastError());
   }

   FileFlush(file_handle); // Force l'écriture sur disque
   FileClose(file_handle);
   Print("✅ Fichier CSV fermé avec succès");
   Print("📁 Localisation: MQL5/Files/Common/ ou Tester/Files/");
   Print("=== FIN EXPORT CSV TRADES - MULTI-PAIRS ===");
}

//======================== [ADDED] OnTesterDeinit ========================
void OnTesterDeinit()
{
   Print("🚀 === OnTesterDeinit appelé - Export automatique ===");
   ExportTradeHistoryCSV();
   Print("🏁 === Fin OnTesterDeinit ===");
}
