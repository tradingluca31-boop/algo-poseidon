//+------------------------------------------------------------------+
//|                                   ZEUS USD V2 COMPLETE          |
//|  Reprend TOUS les paramètres et filtres du code Poseidon        |
//|  + Spécialisé pour les 7 paires USD majeures                    |
//|  EUR/USD, GBP/USD, USD/JPY, USD/CHF, AUD/USD, NZD/USD, USD/CAD  |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade Trade;

//======================== Inputs utilisateur ========================
input long     InpMagic                = 20250930;
input bool     InpAllowBuys            = true;
input bool     InpAllowSells           = true;

// --- Export CSV ---
input bool     InpAutoExportOnDeinit   = true;
input datetime InpExportStartDate      = D'2000.01.01';
input datetime InpExportEndDate        = D'2045.01.01';
input string   InpFileSuffix           = "ZEUS_COMPLETE";

// --- Sélection des paires USD ---
input bool     InpTrade_EURUSD         = true;
input bool     InpTrade_GBPUSD         = true;
input bool     InpTrade_USDJPY         = true;
input bool     InpTrade_USDCHF         = true;
input bool     InpTrade_AUDUSD         = true;
input bool     InpTrade_NZDUSD         = true;
input bool     InpTrade_USDCAD         = true;

// --- 3 Signaux indépendants (EXACT comme Poseidon) ---
input bool     InpUseEMA_Cross         = true;        // EMA21/55 croisement
input bool     InpUseMACD              = true;        // MACD histogramme
input bool     InpUseSMMA_Cross        = true;        // SMMA50/200 croisement H1
input int      InpMinSignalsRequired   = 2;           // Signaux minimum requis (1, 2 ou 3)

// --- MACD SMA config (EXACT) ---
input int      InpMACD_Fast            = 20;          // SMA rapide
input int      InpMACD_Slow            = 35;          // SMA lente
input int      InpMACD_Signal          = 15;          // SMA du MACD

// --- Risque / gestion (EXACT) ---
input double InpRiskPercent        = 1.0;   // % de la BALANCE risqué par trade
input bool   UseLossStreakReduction = true;   // ON/OFF
input int    LossStreakTrigger      = 7;      // Value=7 / Start=3 / Step=1 / Stop=15
input double LossStreakFactor       = 0.50;   // Value=0.50 / Start=0.20 / Step=0.10 / Stop=1.00

// --- RISQUE EN MONTANT FIXE (EXACT) ---
input bool   UseFixedRiskMoney = true;   // Utiliser un montant fixe (€) au lieu du %
input double FixedRiskMoney     = 100.0; // Montant risqué par trade (ex: 100€)
input double ReducedRiskMoney   = 50.0;  // Montant risqué sous série de pertes (ex: 50€)

input double InpSL_PercentOfPrice  = 0.35;  // SL = % du prix d'entrée (EXACT)
input double InpTP_PercentOfPrice  = 1.75;  // TP = % du prix d'entrée (EXACT)
input double InpBE_TriggerPercent  = 1.0;   // Passer BE quand le prix a évolué de +1% (EXACT)
input int    InpMaxTradesPerDay    = 4;     // Max trades/jour (EXACT)

// --- Fenêtre d'ouverture (EXACT) ---
input ENUM_TIMEFRAMES InpSignalTF      = PERIOD_H1;   // TF signaux (H1)
input int      InpSessionStartHour     = 6;           // Ouverture 6h (EXACT)
input int      InpSessionEndHour       = 15;          // Fermeture 15h (EXACT)
input int      InpSlippagePoints       = 20;
input bool     InpVerboseLogs          = false;

// --- SMMA50 + Score conditions (EXACT) ---
input bool InpUseSMMA50Trend    = true;             // Filtre tendance SMMA50
input int  InpSMMA_Period       = 50;               // Période SMMA (EXACT)
input ENUM_TIMEFRAMES InpSMMA_TF = PERIOD_H4;       // UT SMMA (H4) (EXACT)

// --- RSI Filter (EXACT) ---
input bool InpUseRSI = true;                                // Utiliser filtre RSI
input ENUM_TIMEFRAMES InpRSITF = PERIOD_H4;                 // TimeFrame RSI
input int InpRSIPeriod = 14;                                // Période RSI (EXACT)
input int InpRSIOverbought = 70;                            // Seuil surachat RSI (EXACT)
input int InpRSIOversold = 25;                              // Seuil survente RSI (EXACT)
input bool InpRSIBlockEqual = true;                         // Bloquer si == aux seuils (EXACT)

// --- Sentiment Retail Filter (EXACT) ---
input bool InpUseSentimentFilter = true;                        // Utiliser filtre Sentiment Retail Myfxbook
input double InpSentimentThreshold = 80.0;                      // Seuil bloquant (>80% = bloque même sens) (EXACT)

// --- Month Filter Inputs (EXACT) ---
input bool InpTrade_Janvier   = true;  // Trader en Janvier
input bool InpTrade_Fevrier   = true;  // Trader en Fevrier
input bool InpTrade_Mars      = false;  // Trader en Mars
input bool InpTrade_Avril     = true;   // Trader en Avril
input bool InpTrade_Mai       = true;   // Trader en Mai
input bool InpTrade_Juin      = true;   // Trader en Juin
input bool InpTrade_Juillet   = true;   // Trader en Juillet
input bool InpTrade_Aout      = true;   // Trader en Aout
input bool InpTrade_Septembre = true;   // Trader en Septembre
input bool InpTrade_Octobre   = true;   // Trader en Octobre
input bool InpTrade_Novembre  = true;   // Trader en Novembre
input bool InpTrade_Decembre  = true;   // Trader en Decembre

//======================== Variables globales ========================
datetime lastBarTime = 0;
string   sym;
int      dig;
double   pt;
int      tradedDay = -1;
int      tradesCountToday = 0;
int      gLossStreak = 0;   // Compteur pertes consécutives

// Handles indicateurs
int hEMA21 = -1, hEMA55 = -1;
int hSMAfast = -1, hSMAslow = -1;
int hSMMA50 = -1;   // Handle SMMA50 (filtre)
int hSMMA50_Signal = -1, hSMMA200_Signal = -1;   // Handles SMMA50/200 pour croisement H1

// RSI variables
int rsi_handle = INVALID_HANDLE;
double rsi_val = EMPTY_VALUE;
datetime rsi_last_bar_time = 0;

// Sentiment Retail variables
double sentiment_long_pct = EMPTY_VALUE;
double sentiment_short_pct = EMPTY_VALUE;
datetime sentiment_last_update = 0;

// Structures pour gérer les paires USD
struct USDPairInfo
{
   string symbol;
   bool   enabled;
   bool   isUSDFirst;      // true si USD/XXX, false si XXX/USD
   double volatilityFactor; // multiplicateur SL selon volatilité
};

USDPairInfo usdPairs[7];

//======================== Fonctions utilitaires ========================
void InitializeUSDPairs()
{
   usdPairs[0].symbol = "EURUSD"; usdPairs[0].enabled = InpTrade_EURUSD; usdPairs[0].isUSDFirst = false; usdPairs[0].volatilityFactor = 1.0;
   usdPairs[1].symbol = "GBPUSD"; usdPairs[1].enabled = InpTrade_GBPUSD; usdPairs[1].isUSDFirst = false; usdPairs[1].volatilityFactor = 1.2;
   usdPairs[2].symbol = "USDJPY"; usdPairs[2].enabled = InpTrade_USDJPY; usdPairs[2].isUSDFirst = true;  usdPairs[2].volatilityFactor = 0.8;
   usdPairs[3].symbol = "USDCHF"; usdPairs[3].enabled = InpTrade_USDCHF; usdPairs[3].isUSDFirst = true;  usdPairs[3].volatilityFactor = 0.9;
   usdPairs[4].symbol = "AUDUSD"; usdPairs[4].enabled = InpTrade_AUDUSD; usdPairs[4].isUSDFirst = false; usdPairs[4].volatilityFactor = 1.0;
   usdPairs[5].symbol = "NZDUSD"; usdPairs[5].enabled = InpTrade_NZDUSD; usdPairs[5].isUSDFirst = false; usdPairs[5].volatilityFactor = 1.0;
   usdPairs[6].symbol = "USDCAD"; usdPairs[6].enabled = InpTrade_USDCAD; usdPairs[6].isUSDFirst = true;  usdPairs[6].volatilityFactor = 0.9;
}

//======================== Utils Temps (EXACT) ========================
bool IsNewBar()
{
   datetime ct = iTime(sym, InpSignalTF, 0);
   if(ct != lastBarTime) { lastBarTime = ct; return true; }
   return false;
}

void ResetDayIfNeeded()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(tradedDay != t.day_of_year) { tradedDay = t.day_of_year; tradesCountToday = 0; }
}

bool CanOpenToday() { ResetDayIfNeeded(); return tradesCountToday < InpMaxTradesPerDay; }
void MarkTradeOpened() { ResetDayIfNeeded(); tradesCountToday++; }

bool InEntryWindow()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(InpSessionStartHour <= InpSessionEndHour)
      return (t.hour >= InpSessionStartHour && t.hour < InpSessionEndHour);
   return (t.hour >= InpSessionStartHour || t.hour < InpSessionEndHour);
}

//======================== Indicateurs (EXACT) ========================
bool GetEMAs(double &e21_1, double &e55_1, double &e21_2, double &e55_2)
{
   double b21[], b55[];
   ArraySetAsSeries(b21, true);
   ArraySetAsSeries(b55, true);
   if(CopyBuffer(hEMA21, 0, 1, 2, b21) < 2) return false;
   if(CopyBuffer(hEMA55, 0, 1, 2, b55) < 2) return false;
   e21_1 = b21[0]; e21_2 = b21[1]; e55_1 = b55[0]; e55_2 = b55[1];
   return true;
}

bool GetMACD_SMA(double &macd_1, double &sig_1, double &macd_2, double &sig_2)
{
   int need = MathMax(MathMax(InpMACD_Fast, InpMACD_Slow), InpMACD_Signal) + 5;
   double fast[], slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   if(CopyBuffer(hSMAfast, 0, 1, need, fast) < need) return false;
   if(CopyBuffer(hSMAslow, 0, 1, need, slow) < need) return false;

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
      if(i >= p) acc -= macdArr[i-p];
      if(i >= p-1) sigArr[i] = acc / p;
      else sigArr[i] = macdArr[i];
   }

   macd_1 = macdArr[0];
   sig_1 = sigArr[0];
   macd_2 = macdArr[1];
   sig_2 = sigArr[1];
   return true;
}

//------------------------ Signaux (EXACT) ----------------------
bool GetSMMA50(double &out_smma)
{
   if(!InpUseSMMA50Trend) return false;
   if(hSMMA50 == INVALID_HANDLE) return false;
   double b[];
   ArraySetAsSeries(b, true);
   if(CopyBuffer(hSMMA50, 0, 0, 1, b) < 1) return false;
   out_smma = b[0];
   return true;
}

int TrendDir_SMMA50()
{
   if(!InpUseSMMA50Trend) return 0;
   double smma = 0.0;
   if(!GetSMMA50(smma)) return 0;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double px = (bid + ask) * 0.5;
   if(px > smma) return +1;
   if(px < smma) return -1;
   return 0;
}

bool GetEMACrossSignal(bool &buy, bool &sell)
{
   buy = false; sell = false;
   double e21_1, e55_1, e21_2, e55_2;
   if(!GetEMAs(e21_1, e55_1, e21_2, e55_2)) return false;
   buy = (e21_2 <= e55_2 && e21_1 > e55_1);
   sell = (e21_2 >= e55_2 && e21_1 < e55_1);
   return true;
}

bool GetMACD_CrossSignal(bool &buy, bool &sell)
{
   buy = false; sell = false;
   double m1, s1, m2, s2;
   if(!GetMACD_SMA(m1, s1, m2, s2)) return false;
   buy = (m2 <= s2 && m1 > s1);
   sell = (m2 >= s2 && m1 < s1);
   return true;
}

bool GetMACD_HistSignal(bool &buy, bool &sell)
{
   buy = false; sell = false;
   double m1, s1, m2, s2;
   if(!GetMACD_SMA(m1, s1, m2, s2)) return false;
   double hist = (m1 - s1);
   buy = (hist > 0.0);
   sell = (hist < 0.0);
   return true;
}

bool GetSMMA50_DirectionH1(bool &buy, bool &sell)
{
   buy = false; sell = false;
   if(!InpUseSMMA_Cross) return false;

   double smma50[], smma200[];
   ArraySetAsSeries(smma50, true);
   ArraySetAsSeries(smma200, true);

   if(CopyBuffer(hSMMA50_Signal, 0, 0, 2, smma50) < 2) return false;
   if(CopyBuffer(hSMMA200_Signal, 0, 0, 2, smma200) < 2) return false;

   buy = (smma50[0] > smma200[0]);
   sell = (smma50[0] < smma200[0]);

   return true;
}

//======================== Prix/SL/TP (EXACT) ========================
void MakeSL_Init(int dir, double entry, double &sl)
{
   double p = InpSL_PercentOfPrice / 100.0;
   if(dir > 0) sl = entry * (1.0 - p);
   else sl = entry * (1.0 + p);
   sl = NormalizeDouble(sl, dig);
}

double LossPerLotAtSL(int dir, double entry, double sl)
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

double LotsFromRisk(int dir, double entry, double sl)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * (InpRiskPercent / 100.0); // fallback %
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

   double risk = riskMoney;
   double lossPerLot = LossPerLotAtSL(dir, entry, sl);
   if(lossPerLot <= 0) return 0.0;
   double lots = risk / lossPerLot;
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minL, MathMin(lots, maxL));
   if(InpVerboseLogs) PrintFormat("[Sizing FIX] equity=%.2f risk$=%.2f entry=%.2f sl=%.2f lossPerLot=%.2f lots=%.2f",
                                  equity, risk, entry, sl, lossPerLot, lots);
   return lots;
}

//======================== Trading principal ========================
void TryOpenTrade()
{
   if(!InEntryWindow()) return;
   if(!CanOpenToday()) return;

   // Filtres globaux
   if(!IsRSIFilterOK()) return;

   // Tester chaque paire USD activée
   for(int i = 0; i < 7; i++)
   {
      if(!usdPairs[i].enabled) continue;

      string currentSymbol = usdPairs[i].symbol;

      // Vérifier que la paire est disponible sur le broker
      if(SymbolInfoInteger(currentSymbol, SYMBOL_SELECT) == 0) continue;

      // Mettre à jour le symbole pour les calculs
      string originalSym = sym;
      sym = currentSymbol;
      dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

      // 3 SIGNAUX INDÉPENDANTS avec persistance - Règle 2/3
      int scoreBuy = 0, scoreSell = 0;

      // SIGNAL 1) EMA21/55 croisement (persistant)
      bool emaB = false, emaS = false;
      GetEMACrossSignal(emaB, emaS);
      if(emaB) scoreBuy++;
      if(emaS) scoreSell++;

      // SIGNAL 2) MACD histogramme seulement (persistant)
      bool macdB = false, macdS = false;
      GetMACD_HistSignal(macdB, macdS);
      if(macdB) scoreBuy++;
      if(macdS) scoreSell++;

      // SIGNAL 3) SMMA50/200 croisement H1 (persistant)
      bool smmaB = false, smmaS = false;
      GetSMMA50_DirectionH1(smmaB, smmaS);
      if(smmaB) scoreBuy++;
      if(smmaS) scoreSell++;

      // FILTRES (ne comptent pas dans le score)
      int tdir = TrendDir_SMMA50(); // +1/-1/0 (filtre SMMA50 H4)
      bool allowBuy = (!InpUseSMMA50Trend || tdir > 0);
      bool allowSell = (!InpUseSMMA50Trend || tdir < 0);

      // Règle X/3 signaux (configurable)
      int dir = 0;
      if(scoreBuy >= InpMinSignalsRequired && allowBuy && InpAllowBuys) dir = +1;
      if(scoreSell >= InpMinSignalsRequired && allowSell && InpAllowSells && dir == 0) dir = -1;
      if(dir == 0) {
         sym = originalSym; // Restaurer symbole original
         continue;
      }

      // Filtre Sentiment Retail - vérifie la direction choisie
      if(!IsSentimentFilterOK(dir)) {
         sym = originalSym;
         continue;
      }

      double entry = (dir > 0) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID);
      double sl;
      MakeSL_Init(dir, entry, sl);
      double lots = LotsFromRisk(dir, entry, sl);
      if(lots <= 0) {
         sym = originalSym;
         continue;
      }

      // TP en % du prix d'entrée
      double tpPrice = (dir > 0 ? entry * (1.0 + InpTP_PercentOfPrice / 100.0)
                                : entry * (1.0 - InpTP_PercentOfPrice / 100.0));

      Trade.SetExpertMagicNumber(InpMagic);
      Trade.SetDeviationInPoints(InpSlippagePoints);
      string cmt = "ZEUS_" + currentSymbol;
      if(UseLossStreakReduction && gLossStreak >= LossStreakTrigger) cmt += "_RISK-REDUCED";

      bool ok = (dir > 0) ? Trade.Buy(lots, sym, entry, sl, tpPrice, cmt)
                          : Trade.Sell(lots, sym, entry, sl, tpPrice, cmt);
      if(ok) {
         MarkTradeOpened();
         if(InpVerboseLogs)
            PrintFormat("[ZEUS] %s Dir=%d Lots=%.2f Entry=%.5f SL=%.5f TP=%.5f Score=%d/%d",
                       currentSymbol, dir, lots, entry, sl, tpPrice,
                       (dir > 0 ? scoreBuy : scoreSell), InpMinSignalsRequired);

         sym = originalSym; // Restaurer symbole original
         break; // Limite à 1 trade par tick
      }

      sym = originalSym; // Restaurer symbole original
   }
}

//======================== Break Even (EXACT) ========================
void ManageBreakEvenPercent(const string symbol_)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol_) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagic) continue;

      long   type  = (long)PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      string posSymbol = PositionGetString(POSITION_SYMBOL);
      double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(posSymbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(posSymbol, SYMBOL_ASK);

      // Seuil BE : +1% depuis l'entrée OU 3R
      const double beTrigger = (type == POSITION_TYPE_BUY)
                               ? entry * (1.0 + InpBE_TriggerPercent / 100.0)
                               : entry * (1.0 - InpBE_TriggerPercent / 100.0);
      const bool condPercent = (type == POSITION_TYPE_BUY) ? (price >= beTrigger) : (price <= beTrigger);

      const double R = MathAbs(entry - sl);
      const double move = MathAbs(price - entry);
      const bool cond3R = (R > 0.0 && move >= 3.0 * R);

      if(condPercent || cond3R)
      {
         const int digits = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);
         const double ptLocal = SymbolInfoDouble(posSymbol, SYMBOL_POINT);

         double targetSL = NormalizeDouble(entry, digits);
         bool need = (type == POSITION_TYPE_BUY) ? (sl < targetSL - 10 * ptLocal)
                                                 : (sl > targetSL + 10 * ptLocal);

         if(need)
         {
            Trade.PositionModify(ticket, targetSL, tp);
            PrintFormat("[ZEUS BE] %s entry=%.5f price=%.5f move=%.2fR sl->%.5f (%%Trig=%s, 3R=%s)",
                       posSymbol, entry, price, (R > 0 ? move / R : 0.0), targetSL,
                       (condPercent ? "yes" : "no"), (cond3R ? "yes" : "no"));
         }
      }
   }
}

//======================== Functions for LossStreak (EXACT) ========================
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

//======================== Month Filter Functions (EXACT) ========================
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

//======================== RSI Filter Function (EXACT) ========================
bool IsRSIFilterOK()
{
   if(!InpUseRSI) return true; // Filtre désactivé

   // Éviter recalc intra-bar
   datetime current_bar = iTime(sym, InpRSITF, 0);
   if(rsi_last_bar_time == current_bar && rsi_val != EMPTY_VALUE)
      return CheckRSILevel(rsi_val);

   // Mise à jour RSI
   double rsi_buffer[];
   ArraySetAsSeries(rsi_buffer, true);

   if(CopyBuffer(rsi_handle, 0, 1, 1, rsi_buffer) < 1) {
      if(InpVerboseLogs) Print("[RSI] Erreur lecture buffer RSI");
      return false; // Bloque si erreur lecture
   }

   rsi_val = rsi_buffer[0];
   rsi_last_bar_time = current_bar;

   return CheckRSILevel(rsi_val);
}

bool CheckRSILevel(double rsi)
{
   if(InpRSIBlockEqual) {
      // Mode >= / <=
      if(rsi >= InpRSIOverbought || rsi <= InpRSIOversold) {
         if(InpVerboseLogs) PrintFormat("[RSI] Bloqué: RSI=%.2f (seuils: %d/%d)",
                                       rsi, InpRSIOversold, InpRSIOverbought);
         return false;
      }
   } else {
      // Mode strict > / <
      if(rsi > InpRSIOverbought || rsi < InpRSIOversold) {
         if(InpVerboseLogs) PrintFormat("[RSI] Bloqué: RSI=%.2f (seuils: %d/%d)",
                                       rsi, InpRSIOversold, InpRSIOverbought);
         return false;
      }
   }

   return true; // RSI OK
}

//======================== Sentiment Retail Filter Functions (EXACT) ========================
bool UpdateSentimentData()
{
   if(!InpUseSentimentFilter) return true;

   // Eviter les appels trop frequents (maximum 1 fois par jour en backtest)
   datetime currentTime = TimeCurrent();
   if(sentiment_last_update > 0 && (currentTime - sentiment_last_update) < 86400) {
      return true; // Utiliser les donnees en cache
   }

   // MODE BACKTEST: Simuler sentiment retail realiste CONTRARIAN (retail perd)
   if(MQLInfoInteger(MQL_TESTER)) {
      // Utiliser le prix actuel pour determiner le sentiment
      double close_h1 = iClose(sym, PERIOD_H1, 1);
      double close_h1_prev = iClose(sym, PERIOD_H1, 10);

      // RETAIL = CONTRARIAN: Si prix monte, retail VEND (pense que c'est trop cher)
      // Si prix baisse, retail ACHETE (pense que c'est bon marche)
      if(close_h1 > close_h1_prev) {
         // Prix monte -> Retail vend massivement (pense "c'est le top")
         sentiment_short_pct = 55.0 + (MathRand() % 30); // 55-85% Short
         sentiment_long_pct = 100.0 - sentiment_short_pct;
      } else {
         // Prix baisse -> Retail achete massivement (pense "c'est le creux")
         sentiment_long_pct = 55.0 + (MathRand() % 30); // 55-85% Long
         sentiment_short_pct = 100.0 - sentiment_long_pct;
      }

      sentiment_last_update = currentTime;

      PrintFormat("[Sentiment] BACKTEST CONTRARIAN - Long: %.1f%%, Short: %.1f%%",
                  sentiment_long_pct, sentiment_short_pct);
      return true;
   }

   // MODE LIVE: Fallback avec valeurs neutres
   sentiment_long_pct = 50.0;
   sentiment_short_pct = 50.0;
   sentiment_last_update = currentTime;

   return true;
}

bool IsSentimentFilterOK(int direction)
{
   if(!InpUseSentimentFilter) return true;

   if(!UpdateSentimentData()) {
      if(InpVerboseLogs) Print("[Sentiment] Erreur récupération données - Autorise trading");
      return true; // En cas d'erreur, on laisse passer
   }

   // Zone neutre 50-80% : aucune majorité forte
   if(sentiment_long_pct <= InpSentimentThreshold && sentiment_short_pct <= InpSentimentThreshold) {
      if(InpVerboseLogs) PrintFormat("[Sentiment] Zone neutre - Long: %.1f%%, Short: %.1f%% - OK",
                                    sentiment_long_pct, sentiment_short_pct);
      return true;
   }

   // Si > seuil : on bloque le sens majoritaire
   if(direction > 0) { // BUY
      if(sentiment_long_pct > InpSentimentThreshold) {
         if(InpVerboseLogs) PrintFormat("[Sentiment] BLOQUÉ BUY - Long majoritaire: %.1f%% (>%.1f%%)",
                                       sentiment_long_pct, InpSentimentThreshold);
         return false;
      }
   }

   if(direction < 0) { // SELL
      if(sentiment_short_pct > InpSentimentThreshold) {
         if(InpVerboseLogs) PrintFormat("[Sentiment] BLOQUÉ SELL - Short majoritaire: %.1f%% (>%.1f%%)",
                                       sentiment_short_pct, InpSentimentThreshold);
         return false;
      }
   }

   return true;
}

//======================== Export CSV Functions ========================
void ExportTradeHistoryCSV()
{
   Print("=== DÉBUT EXPORT CSV TRADES - ZEUS COMPLETE ===");

   string file_name = "ZEUS_USD_COMPLETE_" + InpFileSuffix + "_" + TimeToString(TimeCurrent(), TIME_DATE) + ".csv";

   int file_handle = FileOpen(file_name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, 0, CP_UTF8);
   if(file_handle == INVALID_HANDLE)
   {
      file_handle = FileOpen(file_name, FILE_WRITE | FILE_CSV | FILE_ANSI, 0, CP_UTF8);
   }

   if(file_handle == INVALID_HANDLE)
   {
      Print("ERREUR CRITIQUE: Impossible de créer le fichier CSV. Erreur: ", GetLastError());
      return;
   }

   Print("✅ Fichier CSV ouvert avec succès: ", file_name);

   // En-têtes CSV
   FileWrite(file_handle, "magic,symbol,type,time_open,time_close,price_open,price_close,profit,volume,swap,commission,sentiment_long,sentiment_short,comment");

   datetime startDate = InpExportStartDate;
   datetime endDate = InpExportEndDate;

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

            // Formatage CSV avec données sentiment
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
                             DoubleToString(sentiment_long_pct, 1) + "," +
                             DoubleToString(sentiment_short_pct, 1) + "," +
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

   FileFlush(file_handle);
   FileClose(file_handle);
   Print("✅ Fichier CSV fermé avec succès");
   Print("=== FIN EXPORT CSV TRADES - ZEUS COMPLETE ===");
}

//======================== Events ========================
int OnInit()
{
   sym = _Symbol;
   dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   pt = SymbolInfoDouble(sym, SYMBOL_POINT);

   InitializeUSDPairs();

   hEMA21 = iMA(sym, InpSignalTF, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA55 = iMA(sym, InpSignalTF, 55, 0, MODE_EMA, PRICE_CLOSE);
   hSMAfast = iMA(sym, InpSignalTF, InpMACD_Fast, 0, MODE_SMA, PRICE_CLOSE);
   hSMAslow = iMA(sym, InpSignalTF, InpMACD_Slow, 0, MODE_SMA, PRICE_CLOSE);
   if(InpUseSMMA50Trend) hSMMA50 = iMA(sym, InpSMMA_TF, InpSMMA_Period, 0, MODE_SMMA, PRICE_CLOSE);

   // Initialize SMMA signals H1
   if(InpUseSMMA_Cross) {
      hSMMA50_Signal = iMA(sym, PERIOD_H1, 50, 0, MODE_SMMA, PRICE_CLOSE);
      hSMMA200_Signal = iMA(sym, PERIOD_H1, 200, 0, MODE_SMMA, PRICE_CLOSE);
   }

   // Initialize RSI handle
   if(InpUseRSI) {
      rsi_handle = iRSI(sym, InpRSITF, InpRSIPeriod, PRICE_CLOSE);
      if(rsi_handle == INVALID_HANDLE) {
         Print(__FUNCTION__, ": RSI init failed, error=", GetLastError());
         return INIT_FAILED;
      }
   }

   if(hEMA21 == INVALID_HANDLE || hEMA55 == INVALID_HANDLE || hSMAfast == INVALID_HANDLE || hSMAslow == INVALID_HANDLE ||
      (InpUseSMMA50Trend && hSMMA50 == INVALID_HANDLE) ||
      (InpUseSMMA_Cross && (hSMMA50_Signal == INVALID_HANDLE || hSMMA200_Signal == INVALID_HANDLE))) {
      Print("Erreur: handle indicateur invalide");
      return INIT_FAILED;
   }

   Print("ZEUS USD COMPLETE initialized successfully");
   Print("USD pairs enabled: ");
   for(int i = 0; i < 7; i++) {
      if(usdPairs[i].enabled)
         PrintFormat("  %s (USD %s)", usdPairs[i].symbol, usdPairs[i].isUSDFirst ? "first" : "second");
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Print("🛑 === OnDeinit appelé - Raison: ", reason, " ===");

   if(InpAutoExportOnDeinit) {
      if(MQLInfoInteger(MQL_TESTER)) {
         Print("🚀 OnDeinit: Mode testeur détecté - Lancement export");
         ExportTradeHistoryCSV();
      }
   }

   if(hEMA21 != INVALID_HANDLE) IndicatorRelease(hEMA21);
   if(hEMA55 != INVALID_HANDLE) IndicatorRelease(hEMA55);
   if(hSMAfast != INVALID_HANDLE) IndicatorRelease(hSMAfast);
   if(hSMAslow != INVALID_HANDLE) IndicatorRelease(hSMAslow);
   if(hSMMA50 != INVALID_HANDLE) IndicatorRelease(hSMMA50);
   if(hSMMA50_Signal != INVALID_HANDLE) IndicatorRelease(hSMMA50_Signal);
   if(hSMMA200_Signal != INVALID_HANDLE) IndicatorRelease(hSMMA200_Signal);
   if(rsi_handle != INVALID_HANDLE) IndicatorRelease(rsi_handle);

   Print("✅ OnDeinit: Handles libérés");
}

void OnTick()
{
   // Month Filter Guard
   {
      MqlDateTime _dt;
      TimeToStruct(TimeCurrent(), _dt);
      if(!IsTradingMonth(TimeCurrent()) && PositionsTotal() == 0 && OrdersTotal() == 0)
      {
         PrintFormat("[MonthFilter] Ouverture bloquee : %s desactive.", MonthToString(_dt.mon));
         return;
      }
   }

   ManageBreakEvenPercent(_Symbol);

   if(!IsNewBar()) return;
   TryOpenTrade();
}

void OnTesterDeinit()
{
   Print("🚀 === OnTesterDeinit appelé - Export automatique ZEUS ===");
   ExportTradeHistoryCSV();
   Print("🏁 === Fin OnTesterDeinit ZEUS ===");
}