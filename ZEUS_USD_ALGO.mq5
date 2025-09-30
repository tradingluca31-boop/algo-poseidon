//+------------------------------------------------------------------+
//|                                           ZEUS USD SPECIALIST    |
//|  Algorithme spécialisé pour les 7 paires USD majeures           |
//|  EUR/USD, GBP/USD, USD/JPY, USD/CHF, AUD/USD, NZD/USD, USD/CAD  |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade Trade;

//======================== Inputs utilisateur ========================
input long     InpMagic                = 20250930;
input bool     InpAllowBuys            = true;
input bool     InpAllowSells           = true;

// --- Export CSV Inputs ---
input bool     InpAutoExportOnDeinit   = true;
input datetime InpExportStartDate      = D'2000.01.01';
input datetime InpExportEndDate        = D'2045.01.01';
input string   InpFileSuffix           = "ZEUS";

// --- Sélection des paires USD ---
input bool     InpTrade_EURUSD         = true;
input bool     InpTrade_GBPUSD         = true;
input bool     InpTrade_USDJPY         = true;
input bool     InpTrade_USDCHF         = true;
input bool     InpTrade_AUDUSD         = true;
input bool     InpTrade_NZDUSD         = true;
input bool     InpTrade_USDCAD         = true;

// --- Stratégie DXY (Dollar Index) ---
input bool     InpUseDXYFilter         = true;
input int      InpDXY_EMA_Fast         = 12;
input int      InpDXY_EMA_Slow         = 26;
input ENUM_TIMEFRAMES InpDXY_TF        = PERIOD_H1;

// --- Signaux technique ---
enum SignalMode { EMA_AND_MACD=0, EMA_OR_MACD=1, EMA_ONLY=2, MACD_ONLY=3 };
input SignalMode InpSignalMode         = EMA_AND_MACD;
input int      InpEMA_Fast             = 21;
input int      InpEMA_Slow             = 55;
input int      InpMACD_Fast            = 12;
input int      InpMACD_Slow            = 26;
input int      InpMACD_Signal          = 9;

// --- Gestion du risque USD spécialisée ---
input double   InpRiskPercentBase      = 1.0;
input double   InpRiskMultiplier_EUR   = 1.2;  // EUR/USD plus volatil
input double   InpRiskMultiplier_GBP   = 1.1;  // GBP/USD volatil
input double   InpRiskMultiplier_JPY   = 0.8;  // USD/JPY moins volatil
input double   InpRiskMultiplier_CHF   = 0.9;  // USD/CHF stable
input double   InpRiskMultiplier_AUD   = 1.0;  // AUD/USD normal
input double   InpRiskMultiplier_NZD   = 1.0;  // NZD/USD normal
input double   InpRiskMultiplier_CAD   = 0.9;  // USD/CAD stable

// --- Stop Loss et Take Profit par paire ---
input double   InpSL_EUR               = 0.30;  // % pour EUR/USD
input double   InpSL_GBP               = 0.35;  // % pour GBP/USD
input double   InpSL_JPY               = 0.25;  // % pour USD/JPY
input double   InpSL_CHF               = 0.25;  // % pour USD/CHF
input double   InpSL_AUD               = 0.30;  // % pour AUD/USD
input double   InpSL_NZD               = 0.30;  // % pour NZD/USD
input double   InpSL_CAD               = 0.25;  // % pour USD/CAD

input double   InpTP_EUR               = 1.50;  // % pour EUR/USD
input double   InpTP_GBP               = 1.75;  // % pour GBP/USD
input double   InpTP_JPY               = 1.25;  // % pour USD/JPY
input double   InpTP_CHF               = 1.25;  // % pour USD/CHF
input double   InpTP_AUD               = 1.50;  // % pour AUD/USD
input double   InpTP_NZD               = 1.50;  // % pour NZD/USD
input double   InpTP_CAD               = 1.25;  // % pour USD/CAD

// --- Fenêtres de trading par session ---
input bool     InpTrade_London         = true;   // Session de Londres
input bool     InpTrade_NewYork        = true;   // Session de New York
input bool     InpTrade_Asian          = false;  // Session asiatique
input int      InpLondon_Start         = 8;      // 08:00 GMT
input int      InpLondon_End           = 16;     // 16:00 GMT
input int      InpNewYork_Start        = 13;     // 13:00 GMT
input int      InpNewYork_End          = 21;     // 21:00 GMT
input int      InpAsian_Start          = 23;     // 23:00 GMT
input int      InpAsian_End            = 7;      // 07:00 GMT

// --- Filtre économique USD ---
input bool     InpAvoidNews            = true;
input int      InpNewsAvoidHours       = 2;      // Heures avant/après news
input bool     InpTradeFOMC            = false;  // Trading pendant FOMC
input bool     InpTradeNFP             = false;  // Trading pendant NFP

// --- Paramètres généraux ---
input int      InpMaxTradesPerDay      = 3;
input int      InpMaxTradesPerPair     = 1;
input double   InpBE_TriggerPercent    = 0.60;
input int      InpSlippagePoints       = 30;
input bool     InpVerboseLogs          = true;
input ENUM_TIMEFRAMES InpSignalTF      = PERIOD_H1;

//======================== Variables globales ========================
datetime lastBarTime = 0;
string   sym;
int      dig;
double   pt;
int      tradedDay = -1;
int      tradesCountToday = 0;
int      tradesPerPair[];

// Handles des indicateurs
int hEMA_Fast = -1, hEMA_Slow = -1;
int hMACD = -1;
int hDXY_EMA_Fast = -1, hDXY_EMA_Slow = -1;

// Liste des paires USD
string USD_PAIRS[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD", "USDCAD"};
bool   USD_ENABLED[] = {true, true, true, true, true, true, true};

//======================== Structures ========================
struct PairConfig
{
   string symbol;
   double riskMultiplier;
   double slPercent;
   double tpPercent;
   bool   isUSDFirst;  // true si USD est la devise de base (USD/JPY)
   bool   enabled;
};

PairConfig pairConfigs[7];

//======================== Fonctions utilitaires ========================
void InitializePairConfigs()
{
   // EUR/USD
   pairConfigs[0].symbol = "EURUSD";
   pairConfigs[0].riskMultiplier = InpRiskMultiplier_EUR;
   pairConfigs[0].slPercent = InpSL_EUR;
   pairConfigs[0].tpPercent = InpTP_EUR;
   pairConfigs[0].isUSDFirst = false;
   pairConfigs[0].enabled = InpTrade_EURUSD;

   // GBP/USD
   pairConfigs[1].symbol = "GBPUSD";
   pairConfigs[1].riskMultiplier = InpRiskMultiplier_GBP;
   pairConfigs[1].slPercent = InpSL_GBP;
   pairConfigs[1].tpPercent = InpTP_GBP;
   pairConfigs[1].isUSDFirst = false;
   pairConfigs[1].enabled = InpTrade_GBPUSD;

   // USD/JPY
   pairConfigs[2].symbol = "USDJPY";
   pairConfigs[2].riskMultiplier = InpRiskMultiplier_JPY;
   pairConfigs[2].slPercent = InpSL_JPY;
   pairConfigs[2].tpPercent = InpTP_JPY;
   pairConfigs[2].isUSDFirst = true;
   pairConfigs[2].enabled = InpTrade_USDJPY;

   // USD/CHF
   pairConfigs[3].symbol = "USDCHF";
   pairConfigs[3].riskMultiplier = InpRiskMultiplier_CHF;
   pairConfigs[3].slPercent = InpSL_CHF;
   pairConfigs[3].tpPercent = InpTP_CHF;
   pairConfigs[3].isUSDFirst = true;
   pairConfigs[3].enabled = InpTrade_USDCHF;

   // AUD/USD
   pairConfigs[4].symbol = "AUDUSD";
   pairConfigs[4].riskMultiplier = InpRiskMultiplier_AUD;
   pairConfigs[4].slPercent = InpSL_AUD;
   pairConfigs[4].tpPercent = InpTP_AUD;
   pairConfigs[4].isUSDFirst = false;
   pairConfigs[4].enabled = InpTrade_AUDUSD;

   // NZD/USD
   pairConfigs[5].symbol = "NZDUSD";
   pairConfigs[5].riskMultiplier = InpRiskMultiplier_NZD;
   pairConfigs[5].slPercent = InpSL_NZD;
   pairConfigs[5].tpPercent = InpTP_NZD;
   pairConfigs[5].isUSDFirst = false;
   pairConfigs[5].enabled = InpTrade_NZDUSD;

   // USD/CAD
   pairConfigs[6].symbol = "USDCAD";
   pairConfigs[6].riskMultiplier = InpRiskMultiplier_CAD;
   pairConfigs[6].slPercent = InpSL_CAD;
   pairConfigs[6].tpPercent = InpTP_CAD;
   pairConfigs[6].isUSDFirst = true;
   pairConfigs[6].enabled = InpTrade_USDCAD;

   ArrayResize(tradesPerPair, 7);
   ArrayInitialize(tradesPerPair, 0);
}

PairConfig GetPairConfig(string symbol)
{
   PairConfig empty;
   for(int i = 0; i < 7; i++)
   {
      if(pairConfigs[i].symbol == symbol)
         return pairConfigs[i];
   }
   return empty;
}

//======================== Filtre DXY (Dollar Index) ========================
int GetDXYTrend()
{
   if(!InpUseDXYFilter) return 0;

   // On simule le DXY avec EUR/USD inversé (approximation)
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);

   if(CopyBuffer(hDXY_EMA_Fast, 0, 0, 2, emaFast) < 2) return 0;
   if(CopyBuffer(hDXY_EMA_Slow, 0, 0, 2, emaSlow) < 2) return 0;

   // Trend DXY haussier = USD fort
   if(emaFast[0] > emaSlow[0] && emaFast[1] <= emaSlow[1]) return +1;  // Début trend USD fort
   if(emaFast[0] < emaSlow[0] && emaFast[1] >= emaSlow[1]) return -1;  // Début trend USD faible
   if(emaFast[0] > emaSlow[0]) return +1;  // Continuation USD fort
   if(emaFast[0] < emaSlow[0]) return -1;  // Continuation USD faible

   return 0;
}

//======================== Sessions de trading ========================
bool IsInTradingSession()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int hour = t.hour;

   bool inSession = false;

   if(InpTrade_London)
   {
      if(InpLondon_Start <= InpLondon_End)
         inSession = inSession || (hour >= InpLondon_Start && hour < InpLondon_End);
      else
         inSession = inSession || (hour >= InpLondon_Start || hour < InpLondon_End);
   }

   if(InpTrade_NewYork)
   {
      if(InpNewYork_Start <= InpNewYork_End)
         inSession = inSession || (hour >= InpNewYork_Start && hour < InpNewYork_End);
      else
         inSession = inSession || (hour >= InpNewYork_Start || hour < InpNewYork_End);
   }

   if(InpTrade_Asian)
   {
      if(InpAsian_Start <= InpAsian_End)
         inSession = inSession || (hour >= InpAsian_Start && hour < InpAsian_End);
      else
         inSession = inSession || (hour >= InpAsian_Start || hour < InpAsian_End);
   }

   return inSession;
}

//======================== Signaux de trading ========================
bool GetEMASignal(string symbol, bool &buySignal, bool &sellSignal)
{
   buySignal = false;
   sellSignal = false;

   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);

   if(CopyBuffer(hEMA_Fast, 0, 0, 2, emaFast) < 2) return false;
   if(CopyBuffer(hEMA_Slow, 0, 0, 2, emaSlow) < 2) return false;

   // Croisement EMA
   buySignal = (emaFast[1] <= emaSlow[1] && emaFast[0] > emaSlow[0]);
   sellSignal = (emaFast[1] >= emaSlow[1] && emaFast[0] < emaSlow[0]);

   return true;
}

bool GetMACDSignal(string symbol, bool &buySignal, bool &sellSignal)
{
   buySignal = false;
   sellSignal = false;

   double macdMain[], macdSignal[];
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSignal, true);

   if(CopyBuffer(hMACD, 0, 0, 2, macdMain) < 2) return false;
   if(CopyBuffer(hMACD, 1, 0, 2, macdSignal) < 2) return false;

   // Croisement MACD
   buySignal = (macdMain[1] <= macdSignal[1] && macdMain[0] > macdSignal[0]);
   sellSignal = (macdMain[1] >= macdSignal[1] && macdMain[0] < macdSignal[0]);

   return true;
}

//======================== Gestion des positions ========================
void CalculateLotsAndPrices(string symbol, int direction, double &lots, double &sl, double &tp)
{
   PairConfig config = GetPairConfig(symbol);
   if(config.symbol == "") return;

   double entry = (direction > 0) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                  : SymbolInfoDouble(symbol, SYMBOL_BID);

   // Calcul SL et TP selon la paire
   if(config.isUSDFirst)
   {
      // USD/XXX (USD/JPY, USD/CHF, USD/CAD)
      if(direction > 0)  // Achat USD
      {
         sl = entry * (1.0 - config.slPercent / 100.0);
         tp = entry * (1.0 + config.tpPercent / 100.0);
      }
      else  // Vente USD
      {
         sl = entry * (1.0 + config.slPercent / 100.0);
         tp = entry * (1.0 - config.tpPercent / 100.0);
      }
   }
   else
   {
      // XXX/USD (EUR/USD, GBP/USD, AUD/USD, NZD/USD)
      if(direction > 0)  // Achat XXX (vente USD)
      {
         sl = entry * (1.0 - config.slPercent / 100.0);
         tp = entry * (1.0 + config.tpPercent / 100.0);
      }
      else  // Vente XXX (achat USD)
      {
         sl = entry * (1.0 + config.slPercent / 100.0);
         tp = entry * (1.0 - config.tpPercent / 100.0);
      }
   }

   // Normalisation
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Calcul du lot basé sur le risque
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * InpRiskPercentBase / 100.0 * config.riskMultiplier;

   double lossPerLot = 0.0;
   bool ok = (direction > 0) ? OrderCalcProfit(ORDER_TYPE_BUY, symbol, 1.0, entry, sl, lossPerLot)
                             : OrderCalcProfit(ORDER_TYPE_SELL, symbol, 1.0, entry, sl, lossPerLot);

   if(ok && MathAbs(lossPerLot) > 0)
   {
      lots = riskMoney / MathAbs(lossPerLot);
      double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxL = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

      if(step <= 0) step = 0.01;
      lots = MathFloor(lots / step) * step;
      lots = MathMax(minL, MathMin(lots, maxL));
   }
   else
   {
      lots = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   }
}

bool CanTradeSymbol(string symbol)
{
   PairConfig config = GetPairConfig(symbol);
   if(!config.enabled) return false;

   // Vérifier max trades par paire
   int pairIndex = -1;
   for(int i = 0; i < 7; i++)
   {
      if(pairConfigs[i].symbol == symbol)
      {
         pairIndex = i;
         break;
      }
   }

   if(pairIndex >= 0 && tradesPerPair[pairIndex] >= InpMaxTradesPerPair)
      return false;

   return true;
}

//======================== Fonction principale de trading ========================
void TryOpenTrade()
{
   if(!IsInTradingSession()) return;

   // Vérifier limite quotidienne
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   if(tradedDay != t.day_of_year)
   {
      tradedDay = t.day_of_year;
      tradesCountToday = 0;
      ArrayInitialize(tradesPerPair, 0);
   }

   if(tradesCountToday >= InpMaxTradesPerDay) return;

   // Obtenir le trend DXY
   int dxyTrend = GetDXYTrend();

   // Analyser chaque paire USD activée
   for(int i = 0; i < 7; i++)
   {
      if(!pairConfigs[i].enabled) continue;
      if(!CanTradeSymbol(pairConfigs[i].symbol)) continue;

      string symbol = pairConfigs[i].symbol;

      // Obtenir les signaux
      bool emaBuy = false, emaSell = false;
      bool macdBuy = false, macdSell = false;

      if(!GetEMASignal(symbol, emaBuy, emaSell)) continue;
      if(!GetMACDSignal(symbol, macdBuy, macdSell)) continue;

      // Logique de signaux selon le mode
      bool buySignal = false, sellSignal = false;

      switch(InpSignalMode)
      {
         case EMA_AND_MACD:
            buySignal = emaBuy && macdBuy;
            sellSignal = emaSell && macdSell;
            break;
         case EMA_OR_MACD:
            buySignal = emaBuy || macdBuy;
            sellSignal = emaSell || macdSell;
            break;
         case EMA_ONLY:
            buySignal = emaBuy;
            sellSignal = emaSell;
            break;
         case MACD_ONLY:
            buySignal = macdBuy;
            sellSignal = macdSell;
            break;
      }

      // Filtre DXY
      if(InpUseDXYFilter && dxyTrend != 0)
      {
         if(pairConfigs[i].isUSDFirst)
         {
            // USD/XXX : trend DXY positif = on peut acheter USD
            if(dxyTrend > 0) sellSignal = false;  // Pas de vente USD
            if(dxyTrend < 0) buySignal = false;   // Pas d'achat USD
         }
         else
         {
            // XXX/USD : trend DXY positif = on peut vendre la paire (acheter USD)
            if(dxyTrend > 0) buySignal = false;   // Pas d'achat de la paire
            if(dxyTrend < 0) sellSignal = false;  // Pas de vente de la paire
         }
      }

      // Exécuter les trades
      int direction = 0;
      if(buySignal && InpAllowBuys) direction = 1;
      else if(sellSignal && InpAllowSells) direction = -1;

      if(direction != 0)
      {
         double lots, sl, tp;
         CalculateLotsAndPrices(symbol, direction, lots, sl, tp);

         if(lots > 0)
         {
            Trade.SetExpertMagicNumber(InpMagic);
            Trade.SetDeviationInPoints(InpSlippagePoints);

            string comment = "ZEUS_" + symbol + "_DXY" + IntegerToString(dxyTrend);

            bool success = false;
            if(direction > 0)
               success = Trade.Buy(lots, symbol, 0, sl, tp, comment);
            else
               success = Trade.Sell(lots, symbol, 0, sl, tp, comment);

            if(success)
            {
               tradesCountToday++;
               tradesPerPair[i]++;

               if(InpVerboseLogs)
                  PrintFormat("[ZEUS] Trade %s on %s: Dir=%d, Lots=%.2f, SL=%.5f, TP=%.5f",
                             comment, symbol, direction, lots, sl, tp);
            }
         }
      }
   }
}

//======================== Export CSV ========================
void ExportTradeHistory()
{
   string file_name = "ZEUS_USD_TRADES_" + InpFileSuffix + ".csv";
   int file_handle = FileOpen(file_name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, 0, CP_UTF8);

   if(file_handle == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create CSV file: ", file_name);
      return;
   }

   if(HistorySelect(InpExportStartDate, InpExportEndDate))
   {
      string csv_header = "magic,symbol,type,time_open,time_close,price_open,price_close,stop_loss,take_profit,volume,profit,commission,swap,total_pnl,comment";
      FileWrite(file_handle, csv_header);

      int deals_total = HistoryDealsTotal();
      for(int i = 0; i < deals_total; i++)
      {
         ulong deal_ticket = HistoryDealGetTicket(i);
         if(deal_ticket <= 0) continue;

         long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         if(magic != InpMagic) continue;

         string symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
         long type = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
         long time = HistoryDealGetInteger(deal_ticket, DEAL_TIME);
         double price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
         double volume = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
         double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
         double commission = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
         double swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
         string comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);

         string csv_line = IntegerToString(magic) + "," +
                          symbol + "," +
                          IntegerToString(type) + "," +
                          IntegerToString(time) + "," +
                          IntegerToString(time) + "," +
                          DoubleToString(price, 5) + "," +
                          DoubleToString(price, 5) + "," +
                          "0,0," +
                          DoubleToString(volume, 2) + "," +
                          DoubleToString(profit, 2) + "," +
                          DoubleToString(commission, 2) + "," +
                          DoubleToString(swap, 2) + "," +
                          DoubleToString(profit + commission + swap, 2) + "," +
                          comment;

         FileWrite(file_handle, csv_line);
      }
   }

   FileClose(file_handle);
   Print("ZEUS CSV export completed: ", file_name);
}

//======================== Gestion du Break Even ========================
void ManageBreakEven()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != InpMagic) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      long type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                                        : SymbolInfoDouble(symbol, SYMBOL_ASK);

      PairConfig config = GetPairConfig(symbol);
      double beTrigger = (type == POSITION_TYPE_BUY)
                         ? entry * (1.0 + InpBE_TriggerPercent / 100.0)
                         : entry * (1.0 - InpBE_TriggerPercent / 100.0);

      bool shouldMoveToBE = (type == POSITION_TYPE_BUY) ? (currentPrice >= beTrigger)
                                                        : (currentPrice <= beTrigger);

      if(shouldMoveToBE && sl != entry)
      {
         Trade.PositionModify(ticket, entry, tp);
         if(InpVerboseLogs)
            PrintFormat("[ZEUS BE] Position %s moved to breakeven", symbol);
      }
   }
}

//======================== Fonctions principales ========================
bool IsNewBar()
{
   datetime ct = iTime(_Symbol, InpSignalTF, 0);
   if(ct != lastBarTime)
   {
      lastBarTime = ct;
      return true;
   }
   return false;
}

//======================== OnInit ========================
int OnInit()
{
   sym = _Symbol;
   dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   pt = SymbolInfoDouble(sym, SYMBOL_POINT);

   // Initialiser les configurations des paires
   InitializePairConfigs();

   // Créer les indicateurs
   hEMA_Fast = iMA(_Symbol, InpSignalTF, InpEMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA_Slow = iMA(_Symbol, InpSignalTF, InpEMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   hMACD = iMACD(_Symbol, InpSignalTF, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);

   // Indicateurs DXY (on utilise EUR/USD comme proxy inversé)
   if(InpUseDXYFilter)
   {
      hDXY_EMA_Fast = iMA("EURUSD", InpDXY_TF, InpDXY_EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
      hDXY_EMA_Slow = iMA("EURUSD", InpDXY_TF, InpDXY_EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   }

   if(hEMA_Fast == INVALID_HANDLE || hEMA_Slow == INVALID_HANDLE || hMACD == INVALID_HANDLE)
   {
      Print("ZEUS ERROR: Failed to create indicators");
      return INIT_FAILED;
   }

   Print("ZEUS USD Specialist initialized successfully");
   Print("Trading pairs enabled: ");
   for(int i = 0; i < 7; i++)
   {
      if(pairConfigs[i].enabled)
         PrintFormat("  %s: Risk=%.1f, SL=%.2f%%, TP=%.2f%%",
                    pairConfigs[i].symbol, pairConfigs[i].riskMultiplier,
                    pairConfigs[i].slPercent, pairConfigs[i].tpPercent);
   }

   return INIT_SUCCEEDED;
}

//======================== OnDeinit ========================
void OnDeinit(const int reason)
{
   if(InpAutoExportOnDeinit)
   {
      Print("ZEUS: Starting CSV export...");
      ExportTradeHistory();
   }

   if(hEMA_Fast != INVALID_HANDLE) IndicatorRelease(hEMA_Fast);
   if(hEMA_Slow != INVALID_HANDLE) IndicatorRelease(hEMA_Slow);
   if(hMACD != INVALID_HANDLE) IndicatorRelease(hMACD);
   if(hDXY_EMA_Fast != INVALID_HANDLE) IndicatorRelease(hDXY_EMA_Fast);
   if(hDXY_EMA_Slow != INVALID_HANDLE) IndicatorRelease(hDXY_EMA_Slow);
}

//======================== OnTick ========================
void OnTick()
{
   if(!IsNewBar()) return;

   ManageBreakEven();
   TryOpenTrade();
}

//======================== OnTester ========================
double OnTester()
{
   return 0.0;
}

void OnTesterDeinit()
{
   if(InpAutoExportOnDeinit)
   {
      Print("ZEUS Tester: Starting CSV export...");
      ExportTradeHistory();
   }
}