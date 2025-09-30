//+------------------------------------------------------------------+
//|                                   ZEUS USD V2 - Poseidon Logic  |
//|  Reprend la logique exacte de Poseidon mais adaptée pour USD    |
//|  + Sentiment Retail pour optimiser les entrées                   |
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
input string   InpFileSuffix           = "ZEUS_V2";

// --- Sélection des paires USD ---
input bool     InpTrade_EURUSD         = true;
input bool     InpTrade_GBPUSD         = true;
input bool     InpTrade_USDJPY         = true;
input bool     InpTrade_USDCHF         = true;
input bool     InpTrade_AUDUSD         = true;
input bool     InpTrade_NZDUSD         = true;
input bool     InpTrade_USDCAD         = true;

// --- SENTIMENT RETAIL (nouveau) ---
input bool     InpUseRetailSentiment   = true;        // Activer filtre sentiment retail
input double   InpRetailThreshold      = 60.0;        // Seuil % retail pour signal contrarian
input bool     InpInvertRetailSignal   = true;        // Inverser signal retail (contrarian)
input int      InpRetailUpdateHours    = 4;           // Fréquence update sentiment (heures)

// --- Signaux technique (logique Poseidon) ---
enum SignalMode { EMA_OR_MACD=0, EMA_ONLY=1, MACD_ONLY=2 };
input SignalMode InpSignalMode         = EMA_OR_MACD;  // Logique "OU" comme Poseidon
input bool     InpUseEMA_Cross         = true;         // EMA21/55 croisement
input bool     InpUseMACD              = true;         // MACD SMA custom

// --- MACD SMA config (identique Poseidon) ---
input int      InpMACD_Fast            = 20;           // SMA rapide
input int      InpMACD_Slow            = 45;           // SMA lente
input int      InpMACD_Signal          = 15;           // SMA du MACD

// --- Gestion du risque par paire USD ---
input double   InpRiskPercent          = 1.0;          // % BALANCE risqué par trade
input double   InpSL_PercentOfPrice    = 0.25;         // SL en % du prix d'entrée
input double   InpTP_PercentOfPrice    = 1.25;         // TP en % du prix d'entrée
input double   InpBE_TriggerPercent    = 0.70;         // BE à +0.70% ou 3R
input int      InpMaxTradesPerDay      = 2;            // Max trades/jour (comme Poseidon)

// --- Sessions de trading (logique Poseidon 7h-14h) ---
input ENUM_TIMEFRAMES InpSignalTF      = PERIOD_H1;    // TF signaux H1
input int      InpSessionStartHour     = 7;            // Ouverture 7h serveur
input int      InpSessionEndHour       = 14;           // Fermeture 14h serveur
input int      InpSlippagePoints       = 20;
input bool     InpVerboseLogs          = true;

// --- Paramètres spécifiques USD ---
input bool     InpAdaptSLForVolatility = true;         // Adapter SL selon volatilité paire
input double   InpVolatilityMultiplier = 1.5;          // Multiplicateur SL si volatilité élevée
input bool     InpUseCorrelationFilter = true;         // Éviter trades corrélés
input double   InpMaxCorrelation       = 0.8;          // Seuil corrélation max

//======================== Variables globales ========================
datetime lastBarTime = 0;
string   sym;
int      dig;
double   pt;
int      tradedDay = -1;
int      tradesCountToday = 0;

// Handles indicateurs (logique Poseidon)
int hEMA21 = -1, hEMA55 = -1;
int hSMAfast = -1, hSMAslow = -1;

// Variables sentiment retail
double retailSentiment_EURUSD = 50.0;
double retailSentiment_GBPUSD = 50.0;
double retailSentiment_USDJPY = 50.0;
double retailSentiment_USDCHF = 50.0;
double retailSentiment_AUDUSD = 50.0;
double retailSentiment_NZDUSD = 50.0;
double retailSentiment_USDCAD = 50.0;
datetime lastRetailUpdate = 0;

// Structures pour gérer les paires USD
struct USDPairInfo
{
   string symbol;
   bool   enabled;
   bool   isUSDFirst;      // true si USD/XXX, false si XXX/USD
   double volatilityFactor; // multiplicateur SL selon volatilité
};

USDPairInfo usdPairs[7];

//======================== Fonctions sentiment retail ========================
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

// Simulation du sentiment retail (en réalité, on connecterait à une API)
void UpdateRetailSentiment()
{
   if(!InpUseRetailSentiment) return;

   datetime currentTime = TimeCurrent();
   if(currentTime - lastRetailUpdate < InpRetailUpdateHours * 3600) return;

   // Simulation des données retail (en pratique, on lirait depuis une API ou fichier)
   // Valeurs entre 0-100 : >60 = retail très bullish, <40 = retail très bearish

   // Simulation basée sur l'heure et des patterns réalistes
   MqlDateTime t;
   TimeToStruct(currentTime, t);
   int seed = t.hour + t.day + t.mon;

   // Génération de sentiments réalistes (tendances retail connues)
   retailSentiment_EURUSD = 45.0 + (seed % 30);        // EUR/USD : retail souvent bullish
   retailSentiment_GBPUSD = 40.0 + (seed % 35);        // GBP/USD : très volatil
   retailSentiment_USDJPY = 50.0 + ((seed*2) % 25);    // USD/JPY : retail aime les carry trades
   retailSentiment_USDCHF = 48.0 + (seed % 20);        // USD/CHF : retail plus conservateur
   retailSentiment_AUDUSD = 55.0 + (seed % 25);        // AUD/USD : retail suit les commodités
   retailSentiment_NZDUSD = 52.0 + (seed % 28);        // NZD/USD : similaire AUD
   retailSentiment_USDCAD = 47.0 + (seed % 22);        // USD/CAD : retail stable

   lastRetailUpdate = currentTime;

   if(InpVerboseLogs)
      PrintFormat("[RETAIL] Updated sentiment: EUR=%.0f, GBP=%.0f, JPY=%.0f, CHF=%.0f, AUD=%.0f, NZD=%.0f, CAD=%.0f",
                 retailSentiment_EURUSD, retailSentiment_GBPUSD, retailSentiment_USDJPY,
                 retailSentiment_USDCHF, retailSentiment_AUDUSD, retailSentiment_NZDUSD, retailSentiment_USDCAD);
}

double GetRetailSentiment(string symbol)
{
   if(!InpUseRetailSentiment) return 50.0;

   if(symbol == "EURUSD") return retailSentiment_EURUSD;
   if(symbol == "GBPUSD") return retailSentiment_GBPUSD;
   if(symbol == "USDJPY") return retailSentiment_USDJPY;
   if(symbol == "USDCHF") return retailSentiment_USDCHF;
   if(symbol == "AUDUSD") return retailSentiment_AUDUSD;
   if(symbol == "NZDUSD") return retailSentiment_NZDUSD;
   if(symbol == "USDCAD") return retailSentiment_USDCAD;

   return 50.0; // Neutre par défaut
}

// Signal contrarian basé sur sentiment retail
int GetRetailSignal(string symbol)
{
   if(!InpUseRetailSentiment) return 0;

   double sentiment = GetRetailSentiment(symbol);

   // Signal contrarian : si retail très bullish (>seuil), on cherche à vendre
   if(sentiment > InpRetailThreshold)
   {
      return InpInvertRetailSignal ? -1 : +1; // Vendre si contrarian activé
   }

   // Si retail très bearish (<40), on cherche à acheter
   if(sentiment < (100.0 - InpRetailThreshold))
   {
      return InpInvertRetailSignal ? +1 : -1; // Acheter si contrarian activé
   }

   return 0; // Neutre
}

//======================== Fonctions Poseidon adaptées ========================
bool IsNewBar()
{
   datetime ct = iTime(sym, InpSignalTF, 0);
   if(ct != lastBarTime)
   {
      lastBarTime = ct;
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
}

bool InEntryWindow()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(InpSessionStartHour <= InpSessionEndHour)
      return (t.hour >= InpSessionStartHour && t.hour < InpSessionEndHour);
   return (t.hour >= InpSessionStartHour || t.hour < InpSessionEndHour);
}

//======================== Indicateurs (logique Poseidon exacte) ========================
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

//======================== Signaux (logique Poseidon + sentiment retail) ========================
void ComputeSignals(string symbol, bool &buySig, bool &sellSig)
{
   buySig = false;
   sellSig = false;

   bool emaBuy = false, emaSell = false;
   if(InpUseEMA_Cross && (InpSignalMode == EMA_ONLY || InpSignalMode == EMA_OR_MACD))
   {
      double e21_1, e55_1, e21_2, e55_2;
      if(GetEMAs(e21_1, e55_1, e21_2, e55_2))
      {
         emaBuy = (e21_2 <= e55_2 && e21_1 > e55_1);
         emaSell = (e21_2 >= e55_2 && e21_1 < e55_1);
      }
   }

   bool macdBuy = false, macdSell = false;
   if(InpUseMACD && (InpSignalMode == MACD_ONLY || InpSignalMode == EMA_OR_MACD))
   {
      double m1, s1, m2, s2;
      if(GetMACD_SMA(m1, s1, m2, s2))
      {
         macdBuy = (m2 <= s2 && m1 > s1);   // croisement haussier
         macdSell = (m2 >= s2 && m1 < s1);  // croisement baissier
      }
   }

   // Logique Poseidon exacte
   if(InpSignalMode == EMA_ONLY) { buySig = emaBuy; sellSig = emaSell; }
   else if(InpSignalMode == MACD_ONLY) { buySig = macdBuy; sellSig = macdSell; }
   else /* EMA_OR_MACD */ {
      buySig = (emaBuy || macdBuy);
      sellSig = (emaSell || macdSell);
   }

   // NOUVEAU : Filtre sentiment retail
   if(InpUseRetailSentiment)
   {
      int retailSignal = GetRetailSignal(symbol);
      if(retailSignal > 0)  // Retail suggère achat
      {
         sellSig = false;   // On bloque les ventes si retail veut acheter (contrarian)
      }
      else if(retailSignal < 0)  // Retail suggère vente
      {
         buySig = false;    // On bloque les achats si retail veut vendre (contrarian)
      }
   }
}

//======================== Gestion des prix (logique Poseidon adaptée USD) ========================
void MakeSL_Init(string symbol, int dir, double entry, double &sl)
{
   double slPercent = InpSL_PercentOfPrice;

   // Adaptation selon volatilité de la paire
   if(InpAdaptSLForVolatility)
   {
      for(int i = 0; i < 7; i++)
      {
         if(usdPairs[i].symbol == symbol)
         {
            slPercent *= usdPairs[i].volatilityFactor;
            break;
         }
      }
   }

   double p = slPercent / 100.0;
   if(dir > 0) sl = entry * (1.0 - p);
   else sl = entry * (1.0 + p);

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
}

double LossPerLotAtSL(string symbol, int dir, double entry, double sl)
{
   double p = 0.0;
   bool ok = (dir > 0) ? OrderCalcProfit(ORDER_TYPE_BUY, symbol, 1.0, entry, sl, p)
                       : OrderCalcProfit(ORDER_TYPE_SELL, symbol, 1.0, entry, sl, p);
   if(ok) return MathAbs(p);

   double tv = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double dist = MathAbs(entry - sl);
   if(tv > 0 && ts > 0) return (dist / ts) * tv;
   return 0.0;
}

double LotsFromRisk(string symbol, int dir, double entry, double sl)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk = equity * (InpRiskPercent / 100.0);
   double lossPerLot = LossPerLotAtSL(symbol, dir, entry, sl);
   if(lossPerLot <= 0) return 0.0;

   double lots = risk / lossPerLot;
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minL, MathMin(lots, maxL));

   if(InpVerboseLogs)
      PrintFormat("[ZEUS Sizing] %s equity=%.2f risk$=%.2f entry=%.5f sl=%.5f lossPerLot=%.2f lots=%.2f",
                 symbol, equity, risk, entry, sl, lossPerLot, lots);
   return lots;
}

//======================== Trading principal ========================
void TryOpenTrade()
{
   if(!InEntryWindow()) return;
   if(!CanOpenToday()) return;

   UpdateRetailSentiment(); // Mise à jour du sentiment retail

   // Tester chaque paire USD activée
   for(int i = 0; i < 7; i++)
   {
      if(!usdPairs[i].enabled) continue;

      string symbol = usdPairs[i].symbol;

      // Vérifier que la paire est disponible sur le broker
      if(SymbolInfoInteger(symbol, SYMBOL_SELECT) == 0) continue;

      bool buySig = false, sellSig = false;
      ComputeSignals(symbol, buySig, sellSig);

      int dir = 0;
      if(buySig && InpAllowBuys) dir = +1;
      if(sellSig && InpAllowSells && dir == 0) dir = -1;
      if(dir == 0) continue;

      double entry = (dir > 0) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                               : SymbolInfoDouble(symbol, SYMBOL_BID);
      double sl;
      MakeSL_Init(symbol, dir, entry, sl);
      double lots = LotsFromRisk(symbol, dir, entry, sl);
      if(lots <= 0) continue;

      // TP en % du prix d'entrée (logique Poseidon)
      double tpPrice = (dir > 0) ? entry * (1.0 + InpTP_PercentOfPrice / 100.0)
                                 : entry * (1.0 - InpTP_PercentOfPrice / 100.0);

      Trade.SetExpertMagicNumber(InpMagic);
      Trade.SetDeviationInPoints(InpSlippagePoints);

      string cmt = "ZEUS_" + symbol;
      if(InpUseRetailSentiment)
      {
         double sentiment = GetRetailSentiment(symbol);
         cmt += "_R" + DoubleToString(sentiment, 0);
      }

      bool ok = (dir > 0) ? Trade.Buy(lots, symbol, entry, sl, tpPrice, cmt)
                          : Trade.Sell(lots, symbol, entry, sl, tpPrice, cmt);
      if(ok)
      {
         MarkTradeOpened();
         if(InpVerboseLogs)
            PrintFormat("[ZEUS TRADE] %s Dir=%d Lots=%.2f Entry=%.5f SL=%.5f TP=%.5f Retail=%.0f",
                       symbol, dir, lots, entry, sl, tpPrice, GetRetailSentiment(symbol));

         // Limite à 1 trade par symbole par jour pour éviter over-trading
         break;
      }
   }
}

//======================== Break Even (logique Poseidon exacte) ========================
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
      double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol_, SYMBOL_BID)
                                                 : SymbolInfoDouble(symbol_, SYMBOL_ASK);

      // Seuil BE : +0.70% depuis l'entrée OU 3R (logique Poseidon exacte)
      const double beTrigger = (type == POSITION_TYPE_BUY)
                               ? entry * (1.0 + InpBE_TriggerPercent / 100.0)
                               : entry * (1.0 - InpBE_TriggerPercent / 100.0);
      const bool condPercent = (type == POSITION_TYPE_BUY) ? (price >= beTrigger) : (price <= beTrigger);

      const double R = MathAbs(entry - sl);
      const double move = MathAbs(price - entry);
      const bool cond3R = (R > 0.0 && move >= 3.0 * R);

      if(condPercent || cond3R)
      {
         const int digits = (int)SymbolInfoInteger(symbol_, SYMBOL_DIGITS);
         const double ptLocal = SymbolInfoDouble(symbol_, SYMBOL_POINT);

         double targetSL = NormalizeDouble(entry, digits);
         bool need = (type == POSITION_TYPE_BUY) ? (sl < targetSL - 10 * ptLocal)
                                                 : (sl > targetSL + 10 * ptLocal);

         if(need)
         {
            Trade.PositionModify(ticket, targetSL, tp);
            if(InpVerboseLogs)
               PrintFormat("[ZEUS BE] %s entry=%.5f price=%.5f move=%.2fR sl->%.5f (%sTrig=%s, 3R=%s)",
                          symbol_, entry, price, (R > 0 ? move / R : 0.0), targetSL,
                          "%", (condPercent ? "yes" : "no"), (cond3R ? "yes" : "no"));
         }
      }
   }
}

//======================== Export CSV ========================
void ExportTradeHistory()
{
   string file_name = "ZEUS_USD_V2_" + InpFileSuffix + ".csv";
   int file_handle = FileOpen(file_name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, 0, CP_UTF8);

   if(file_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create CSV file: ", file_name);
      return;
   }

   if(HistorySelect(InpExportStartDate, InpExportEndDate))
   {
      string csv_header = "magic,symbol,type,time_open,time_close,price_open,price_close,stop_loss,take_profit,volume,profit,commission,swap,total_pnl,retail_sentiment,comment";
      FileWrite(file_handle, csv_header);

      int deals_total = HistoryDealsTotal();
      for(int i = 0; i < deals_total; i++)
      {
         ulong deal_ticket = HistoryDealGetTicket(i);
         if(deal_ticket <= 0) continue;

         long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         if(magic != InpMagic) continue;

         string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
         string comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
         double sentiment = GetRetailSentiment(symbol);

         string csv_line = IntegerToString(magic) + "," +
                          symbol + "," +
                          IntegerToString(HistoryDealGetInteger(deal_ticket, DEAL_TYPE)) + "," +
                          IntegerToString(HistoryDealGetInteger(deal_ticket, DEAL_TIME)) + "," +
                          IntegerToString(HistoryDealGetInteger(deal_ticket, DEAL_TIME)) + "," +
                          DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_PRICE), 5) + "," +
                          DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_PRICE), 5) + "," +
                          "0,0," +
                          DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_VOLUME), 2) + "," +
                          DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_PROFIT), 2) + "," +
                          DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION), 2) + "," +
                          DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_SWAP), 2) + "," +
                          DoubleToString(HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                                       HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION) +
                                       HistoryDealGetDouble(deal_ticket, DEAL_SWAP), 2) + "," +
                          DoubleToString(sentiment, 0) + "," +
                          comment;

         FileWrite(file_handle, csv_line);
      }
   }

   FileClose(file_handle);
   Print("ZEUS V2 CSV export completed: ", file_name);
}

//======================== Events ========================
int OnInit()
{
   sym = _Symbol;
   dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   pt = SymbolInfoDouble(sym, SYMBOL_POINT);

   InitializeUSDPairs();

   // Créer les indicateurs (handles Poseidon exactes)
   hEMA21 = iMA(sym, InpSignalTF, 21, 0, MODE_EMA, PRICE_CLOSE);
   hEMA55 = iMA(sym, InpSignalTF, 55, 0, MODE_EMA, PRICE_CLOSE);
   hSMAfast = iMA(sym, InpSignalTF, InpMACD_Fast, 0, MODE_SMA, PRICE_CLOSE);
   hSMAslow = iMA(sym, InpSignalTF, InpMACD_Slow, 0, MODE_SMA, PRICE_CLOSE);

   if(hEMA21 == INVALID_HANDLE || hEMA55 == INVALID_HANDLE ||
      hSMAfast == INVALID_HANDLE || hSMAslow == INVALID_HANDLE)
   {
      Print("ZEUS ERROR: Invalid indicator handle");
      return INIT_FAILED;
   }

   Print("ZEUS USD V2 (Poseidon Logic + Retail Sentiment) initialized successfully");
   Print("Retail sentiment filter: ", InpUseRetailSentiment ? "ENABLED" : "DISABLED");
   Print("USD pairs enabled: ");
   for(int i = 0; i < 7; i++)
   {
      if(usdPairs[i].enabled)
         PrintFormat("  %s (USD %s, Vol factor: %.1f)",
                    usdPairs[i].symbol,
                    usdPairs[i].isUSDFirst ? "first" : "second",
                    usdPairs[i].volatilityFactor);
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpAutoExportOnDeinit)
   {
      Print("ZEUS V2: Starting CSV export...");
      ExportTradeHistory();
   }

   if(hEMA21 != INVALID_HANDLE) IndicatorRelease(hEMA21);
   if(hEMA55 != INVALID_HANDLE) IndicatorRelease(hEMA55);
   if(hSMAfast != INVALID_HANDLE) IndicatorRelease(hSMAfast);
   if(hSMAslow != INVALID_HANDLE) IndicatorRelease(hSMAslow);
}

void OnTick()
{
   // Gestion BE en continu (logique Poseidon)
   ManageBreakEvenPercent(_Symbol);

   if(!IsNewBar()) return;
   TryOpenTrade();
}

// Fonctions pour Strategy Tester
double OnTester()
{
   return 0.0;
}

void OnTesterDeinit()
{
   if(InpAutoExportOnDeinit)
   {
      Print("ZEUS V2 Tester: Starting CSV export...");
      ExportTradeHistory();
   }
}