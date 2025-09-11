//+------------------------------------------------------------------+
//|                                                TEST_4_SMMA_CROSS.mq5 |
//|                                   Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

// Function declarations
void ResetDailyTradeCount();
bool BasicConditionsCheck();
bool IsMonthAllowed(int month);
bool UpdateIndicators();
void CheckTradingSignals();
int GetTradingSignal();
int GetEMACrossSignal();
int GetSMMACrossSignal();
int GetMACDSignal();
bool CheckRSIFilter(bool isBuySignal);
bool CheckSMMAFilter(bool isBuySignal);
double CalculateLotSize();
void ExecuteBuyOrder(double lotSize);
void ExecuteSellOrder(double lotSize);
void ManagePositions();
void CheckBreakEven();
void CreateCSVHeader();
void LogTradeToCSV(string type, double lots, double price, double sl, double tp);

input group "=== SIGNAL GENERATION ==="
input int SignalMode = 1;  // 0=EMA21/55 cross, 1=MACD, 2=SMMA50/200 cross
input bool UseEmaSignal = true;
input bool UseMacdSignal = true;
input bool UseSmmaCrossSignal = true; // Nouveau signal SMMA cross

input group "=== INDICATORS ==="
input int RSI_Period = 14;
input int RSI_UpperLevel = 70;
input int RSI_LowerLevel = 30;
input int EMA21_Period = 21;
input int EMA55_Period = 55;
input int SMMA50_Period = 50;
input int SMMA200_Period = 200; // Nouvelle SMMA200
input int MACD_FastEMA = 12;
input int MACD_SlowEMA = 26;
input int MACD_SignalSMA = 9;

input group "=== RISK MANAGEMENT ==="
input double StopLossPercent = 0.35;
input double RiskPercent = 1.0;
input bool UseFixedMoney = false;
input double FixedMoneyRisk = 50.0;

input group "=== TRADE SETTINGS ==="
input int MaxTradesPerDay = 4;
input int StartHour = 6;
input int EndHour = 15;
input double TakeProfit = 500.0;

input group "=== FILTERS ==="
input bool UseRSIFilter = true;
input bool UseSMMAFilter = true;
input bool UseMonthlyFilter = false;
input bool TradeJanuary = true;
input bool TradeFebruary = true;
input bool TradeMarch = true;
input bool TradeApril = true;
input bool TradeMay = true;
input bool TradeJune = true;
input bool TradeJuly = true;
input bool TradeAugust = true;
input bool TradeSeptember = true;
input bool TradeOctober = true;
input bool TradeNovember = true;
input bool TradeDecember = true;

input group "=== LOSS STREAK REDUCTION ==="
input bool UseLossStreakReduction = true;
input int LossStreakThreshold = 3;
input double LossStreakRiskReduction = 0.5;

input group "=== LOGGING ==="
input bool EnableLogging = true;
input bool ExportToCSV = true;

// Handles for indicators
int handleRSI;
int handleEMA21;
int handleEMA55;
int handleSMMA50_H1; // Pour signal SMMA cross
int handleSMMA50_H4; // Pour filtre
int handleSMMA200; // Nouveau handle pour SMMA200
int handleMACD;

// Global variables
int tradesCount = 0;
datetime lastTradeDate = 0;
int consecutiveLosses = 0;
double currentRiskPercent;
string csvFileName;

// Arrays for indicator values
double rsiValues[];
double ema21Values[];
double ema55Values[];
double smma50H1Values[]; // Pour signal cross
double smma50H4Values[]; // Pour filtre
double smma200Values[]; // Nouveau array pour SMMA200
double macdMainValues[];
double macdSignalValues[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   currentRiskPercent = RiskPercent;
   
   // Initialize indicators
   handleRSI = iRSI(_Symbol, PERIOD_H4, RSI_Period, PRICE_CLOSE); // RSI en H4
   handleEMA21 = iMA(_Symbol, PERIOD_H1, EMA21_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA55 = iMA(_Symbol, PERIOD_H1, EMA55_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleSMMA50_H1 = iMA(_Symbol, PERIOD_H1, SMMA50_Period, 0, MODE_SMMA, PRICE_CLOSE); // SMMA50 H1 pour signal
   handleSMMA50_H4 = iMA(_Symbol, PERIOD_H4, SMMA50_Period, 0, MODE_SMMA, PRICE_CLOSE); // SMMA50 H4 pour filtre
   handleSMMA200 = iMA(_Symbol, PERIOD_H1, SMMA200_Period, 0, MODE_SMMA, PRICE_CLOSE); // SMMA200 H1 pour signal
   handleMACD = iMACD(_Symbol, PERIOD_H1, MACD_FastEMA, MACD_SlowEMA, MACD_SignalSMA, PRICE_CLOSE);
   
   // Check if all indicators are valid
   if(handleRSI == INVALID_HANDLE || handleEMA21 == INVALID_HANDLE || 
      handleEMA55 == INVALID_HANDLE || handleSMMA50_H1 == INVALID_HANDLE || 
      handleSMMA50_H4 == INVALID_HANDLE || handleSMMA200 == INVALID_HANDLE || handleMACD == INVALID_HANDLE)
   {
      Print("Error creating indicators");
      return(INIT_FAILED);
   }
   
   // Setup CSV export
   if(ExportToCSV)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      csvFileName = StringFormat("%s_trades_%04d%02d%02d.csv", _Symbol, dt.year, dt.mon, dt.day);
      CreateCSVHeader();
   }
   
   Print("Expert Advisor initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   if(handleRSI != INVALID_HANDLE) IndicatorRelease(handleRSI);
   if(handleEMA21 != INVALID_HANDLE) IndicatorRelease(handleEMA21);
   if(handleEMA55 != INVALID_HANDLE) IndicatorRelease(handleEMA55);
   if(handleSMMA50_H1 != INVALID_HANDLE) IndicatorRelease(handleSMMA50_H1);
   if(handleSMMA50_H4 != INVALID_HANDLE) IndicatorRelease(handleSMMA50_H4);
   if(handleSMMA200 != INVALID_HANDLE) IndicatorRelease(handleSMMA200);
   if(handleMACD != INVALID_HANDLE) IndicatorRelease(handleMACD);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;
   
   // Reset daily trade count
   ResetDailyTradeCount();
   
   // Check basic conditions
   if(!BasicConditionsCheck()) return;
   
   // Update indicators
   if(!UpdateIndicators()) return;
   
   // Check for trading signals
   CheckTradingSignals();
   
   // Manage open positions
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Reset daily trade count                                          |
//+------------------------------------------------------------------+
void ResetDailyTradeCount()
{
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   
   MqlDateTime lastTime;
   TimeToStruct(lastTradeDate, lastTime);
   
   if(currentTime.day != lastTime.day || currentTime.mon != lastTime.mon || currentTime.year != lastTime.year)
   {
      tradesCount = 0;
   }
}

//+------------------------------------------------------------------+
//| Check basic trading conditions                                   |
//+------------------------------------------------------------------+
bool BasicConditionsCheck()
{
   // Check trading hours
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   if(currentTime.hour < StartHour || currentTime.hour >= EndHour) return false;
   
   // Check maximum trades per day
   if(tradesCount >= MaxTradesPerDay) return false;
   
   // Check monthly filter
   if(UseMonthlyFilter && !IsMonthAllowed(currentTime.mon)) return false;
   
   // Check if already have position
   if(PositionsTotal() > 0) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if month is allowed for trading                           |
//+------------------------------------------------------------------+
bool IsMonthAllowed(int month)
{
   switch(month)
   {
      case 1: return TradeJanuary;
      case 2: return TradeFebruary;
      case 3: return TradeMarch;
      case 4: return TradeApril;
      case 5: return TradeMay;
      case 6: return TradeJune;
      case 7: return TradeJuly;
      case 8: return TradeAugust;
      case 9: return TradeSeptember;
      case 10: return TradeOctober;
      case 11: return TradeNovember;
      case 12: return TradeDecember;
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| Update indicator values                                          |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   ArraySetAsSeries(rsiValues, true);
   ArraySetAsSeries(ema21Values, true);
   ArraySetAsSeries(ema55Values, true);
   ArraySetAsSeries(smma50H1Values, true); // SMMA50 H1
   ArraySetAsSeries(smma50H4Values, true); // SMMA50 H4
   ArraySetAsSeries(smma200Values, true);
   ArraySetAsSeries(macdMainValues, true);
   ArraySetAsSeries(macdSignalValues, true);
   
   if(CopyBuffer(handleRSI, 0, 0, 3, rsiValues) <= 0) return false;
   if(CopyBuffer(handleEMA21, 0, 0, 3, ema21Values) <= 0) return false;
   if(CopyBuffer(handleEMA55, 0, 0, 3, ema55Values) <= 0) return false;
   if(CopyBuffer(handleSMMA50_H1, 0, 0, 3, smma50H1Values) <= 0) return false; // SMMA50 H1 pour signal
   if(CopyBuffer(handleSMMA50_H4, 0, 0, 3, smma50H4Values) <= 0) return false; // SMMA50 H4 pour filtre
   if(CopyBuffer(handleSMMA200, 0, 0, 3, smma200Values) <= 0) return false;
   if(CopyBuffer(handleMACD, 0, 0, 3, macdMainValues) <= 0) return false;
   if(CopyBuffer(handleMACD, 1, 0, 3, macdSignalValues) <= 0) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for trading signals                                        |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
   int signal = GetTradingSignal();
   
   if(signal != 0)
   {
      double lotSize = CalculateLotSize();
      if(lotSize > 0)
      {
         if(signal > 0)
            ExecuteBuyOrder(lotSize);
         else
            ExecuteSellOrder(lotSize);
      }
   }
}

//+------------------------------------------------------------------+
//| Get trading signal based on selected mode                       |
//+------------------------------------------------------------------+
int GetTradingSignal()
{
   int score = 0;
   
   // EMA Cross Signal
   if(UseEmaSignal)
   {
      int emaSignal = GetEMACrossSignal();
      score += emaSignal;
   }
   
   // MACD Signal
   if(UseMacdSignal)
   {
      int macdSignal = GetMACDSignal();
      score += macdSignal;
   }
   
   // SMMA Cross Signal (nouveau)
   if(UseSmmaCrossSignal)
   {
      int smmaCrossSignal = GetSMMACrossSignal();
      score += smmaCrossSignal;
   }
   
   // Apply filters
   if(UseRSIFilter && !CheckRSIFilter(score > 0)) return 0;
   if(UseSMMAFilter && !CheckSMMAFilter(score > 0)) return 0;
   
   // Require minimum score
   if(MathAbs(score) < 1) return 0;
   
   return score > 0 ? 1 : -1;
}

//+------------------------------------------------------------------+
//| Get EMA crossover signal                                         |
//+------------------------------------------------------------------+
int GetEMACrossSignal()
{
   // Current and previous EMA values
   double ema21_current = ema21Values[0];
   double ema21_previous = ema21Values[1];
   double ema55_current = ema55Values[0];
   double ema55_previous = ema55Values[1];
   
   // Bullish crossover: EMA21 crosses above EMA55
   if(ema21_previous <= ema55_previous && ema21_current > ema55_current)
      return 1;
   
   // Bearish crossover: EMA21 crosses below EMA55
   if(ema21_previous >= ema55_previous && ema21_current < ema55_current)
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Get SMMA crossover signal (nouveau)                             |
//+------------------------------------------------------------------+
int GetSMMACrossSignal()
{
   // Current and previous SMMA values (H1 pour le signal)
   double smma50_current = smma50H1Values[0];
   double smma50_previous = smma50H1Values[1];
   double smma200_current = smma200Values[0];
   double smma200_previous = smma200Values[1];
   
   // Bullish crossover: SMMA50 crosses above SMMA200
   if(smma50_previous <= smma200_previous && smma50_current > smma200_current)
   {
      if(EnableLogging) Print("SMMA Cross Signal: BULLISH - SMMA50 crosses above SMMA200");
      return 1;
   }
   
   // Bearish crossover: SMMA50 crosses below SMMA200
   if(smma50_previous >= smma200_previous && smma50_current < smma200_current)
   {
      if(EnableLogging) Print("SMMA Cross Signal: BEARISH - SMMA50 crosses below SMMA200");
      return -1;
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Get MACD signal                                                  |
//+------------------------------------------------------------------+
int GetMACDSignal()
{
   double macd_current = macdMainValues[0];
   double macd_previous = macdMainValues[1];
   double signal_current = macdSignalValues[0];
   double signal_previous = macdSignalValues[1];
   
   // Bullish signal: MACD crosses above signal line
   if(macd_previous <= signal_previous && macd_current > signal_current)
      return 1;
   
   // Bearish signal: MACD crosses below signal line
   if(macd_previous >= signal_previous && macd_current < signal_current)
      return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
//| Check RSI filter                                                 |
//+------------------------------------------------------------------+
bool CheckRSIFilter(bool isBuySignal)
{
   double rsi_current = rsiValues[0];
   
   if(isBuySignal && rsi_current >= RSI_UpperLevel) return false;
   if(!isBuySignal && rsi_current <= RSI_LowerLevel) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check SMMA filter                                                |
//+------------------------------------------------------------------+
bool CheckSMMAFilter(bool isBuySignal)
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double smma50_h4 = smma50H4Values[0]; // Utilise SMMA50 H4 pour le filtre
   
   if(isBuySignal && price < smma50_h4) return false;
   if(!isBuySignal && price > smma50_h4) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   double lotSize;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   if(UseFixedMoney)
   {
      double adjustedRisk = FixedMoneyRisk;
      if(UseLossStreakReduction && consecutiveLosses >= LossStreakThreshold)
         adjustedRisk *= LossStreakRiskReduction;
      
      double stopLossDistance = price * StopLossPercent / 100.0;
      double stopLossTicks = stopLossDistance / tickSize;
      lotSize = adjustedRisk / (stopLossTicks * tickValue);
   }
   else
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double adjustedRiskPercent = currentRiskPercent;
      
      if(UseLossStreakReduction && consecutiveLosses >= LossStreakThreshold)
         adjustedRiskPercent *= LossStreakRiskReduction;
      
      double riskAmount = balance * adjustedRiskPercent / 100.0;
      double stopLossDistance = price * StopLossPercent / 100.0;
      double stopLossTicks = stopLossDistance / tickSize;
      lotSize = riskAmount / (stopLossTicks * tickValue);
   }
   
   // Normalize lot size
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathMax(lotSize, minLot);
   lotSize = MathMin(lotSize, maxLot);
   lotSize = NormalizeDouble(lotSize / lotStep, 0) * lotStep;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Execute buy order                                                |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(double lotSize)
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = price * (1 - StopLossPercent / 100.0);
   double takeProfit = price + TakeProfit * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(trade.Buy(lotSize, _Symbol, price, stopLoss, takeProfit, "EA Buy"))
   {
      tradesCount++;
      lastTradeDate = TimeCurrent();
      
      if(EnableLogging)
         Print("BUY order executed: ", lotSize, " lots at ", price);
      
      if(ExportToCSV)
         LogTradeToCSV("BUY", lotSize, price, stopLoss, takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Execute sell order                                               |
//+------------------------------------------------------------------+
void ExecuteSellOrder(double lotSize)
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = price * (1 + StopLossPercent / 100.0);
   double takeProfit = price - TakeProfit * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   
   if(trade.Sell(lotSize, _Symbol, price, stopLoss, takeProfit, "EA Sell"))
   {
      tradesCount++;
      lastTradeDate = TimeCurrent();
      
      if(EnableLogging)
         Print("SELL order executed: ", lotSize, " lots at ", price);
      
      if(ExportToCSV)
         LogTradeToCSV("SELL", lotSize, price, stopLoss, takeProfit);
   }
}

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            CheckBreakEven();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check and apply break-even                                       |
//+------------------------------------------------------------------+
void CheckBreakEven()
{
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   long positionType = PositionGetInteger(POSITION_TYPE);
   double currentPrice = (positionType == POSITION_TYPE_BUY) ? 
                         SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                         SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   double profit = PositionGetDouble(POSITION_PROFIT);
   
   if(profit >= 300.0) // Break-even at 300$ profit
   {
      double newStopLoss = openPrice;
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      
      if(positionType == POSITION_TYPE_BUY)
      {
         if(PositionGetDouble(POSITION_SL) < newStopLoss)
         {
            trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
            if(EnableLogging) Print("Break-even applied for BUY position");
         }
      }
      else
      {
         double currentSL = PositionGetDouble(POSITION_SL);
         if(currentSL > newStopLoss || currentSL == 0.0)
         {
            trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
            if(EnableLogging) Print("Break-even applied for SELL position");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Create CSV header                                                |
//+------------------------------------------------------------------+
void CreateCSVHeader()
{
   int fileHandle = FileOpen(csvFileName, FILE_WRITE|FILE_CSV);
   if(fileHandle != INVALID_HANDLE)
   {
      FileWrite(fileHandle, "Date", "Time", "Type", "Lots", "Price", "StopLoss", "TakeProfit", "Profit");
      FileClose(fileHandle);
   }
}

//+------------------------------------------------------------------+
//| Log trade to CSV                                                 |
//+------------------------------------------------------------------+
void LogTradeToCSV(string type, double lots, double price, double sl, double tp)
{
   int fileHandle = FileOpen(csvFileName, FILE_WRITE|FILE_CSV|FILE_READ);
   if(fileHandle != INVALID_HANDLE)
   {
      FileSeek(fileHandle, 0, SEEK_END);
      
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      string dateStr = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
      string timeStr = StringFormat("%02d:%02d:%02d", dt.hour, dt.min, dt.sec);
      
      FileWrite(fileHandle, dateStr, timeStr, type, lots, price, sl, tp, "");
      FileClose(fileHandle);
   }
}

//+------------------------------------------------------------------+
//| Handle trade result                                              |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(HistoryDealSelect(dealTicket))
      {
         double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
         
         if(profit < 0)
            consecutiveLosses++;
         else
            consecutiveLosses = 0;
         
         if(EnableLogging)
            Print("Deal completed. Profit: ", profit, " Consecutive losses: ", consecutiveLosses);
      }
   }
}