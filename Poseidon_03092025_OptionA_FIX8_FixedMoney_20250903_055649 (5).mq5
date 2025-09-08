//+------------------------------------------------------------------+
//|                                         Poseidon_London_1H_fixedRisk.mq5 |
//|                                                                    |
//|                                                                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Input parameters
input group "=== Signal Parameters ==="
input ENUM_TIMEFRAMES Timeframe = PERIOD_H1;                    // Timeframe for analysis
input int             EMA_fast = 21;                            // Fast EMA period
input int             EMA_slow = 55;                            // Slow EMA period
input int             MACD_fast = 12;                           // MACD fast period
input int             MACD_slow = 26;                           // MACD slow period
input int             MACD_signal = 9;                          // MACD signal period

input group "=== Risk Management ==="
input bool            UseFixedRisk = true;                      // Use fixed risk percentage
input double          FixedRisk = 1.0;                          // Fixed risk percentage
input double          FixedMoney = 100.0;                       // Fixed money risk (if UseFixedRisk=false)
input bool            UseStreakRiskReduction = true;            // Use loss streak risk reduction
input int             StreakLength = 3;                         // Loss streak length for risk reduction
input double          StreakRiskReduction = 0.5;               // Risk reduction factor for streak

input group "=== Trading Hours ==="
input int             StartHour = 6;                            // Trading start hour (server time)
input int             EndHour = 15;                             // Trading end hour (server time)

input group "=== Position Management ==="
input int             MaxTradesPerDay = 2;                     // Maximum trades per day
input bool            UseBE = true;                             // Use break-even
input double          BEPoints = 100.0;                        // Break-even points

input group "=== Month Filter ==="
input bool            UseMonthFilter = false;                  // Use month filter
input bool            TradeJanuary = true;                     // Trade in January
input bool            TradeFebruary = true;                    // Trade in February
input bool            TradeMarch = true;                       // Trade in March
input bool            TradeApril = true;                       // Trade in April
input bool            TradeMay = true;                         // Trade in May
input bool            TradeJune = true;                        // Trade in June
input bool            TradeJuly = true;                        // Trade in July
input bool            TradeAugust = true;                      // Trade in August
input bool            TradeSeptember = true;                   // Trade in September
input bool            TradeOctober = true;                     // Trade in October
input bool            TradeNovember = true;                    // Trade in November
input bool            TradeDecember = true;                    // Trade in December

//--- Global variables
double signal_score = 0;
int trades_today = 0;
int loss_streak = 0;
datetime last_trade_date = 0;

//--- Handles for indicators
int handle_ema_fast, handle_ema_slow, handle_macd;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Initialize indicators
    handle_ema_fast = iMA(_Symbol, Timeframe, EMA_fast, 0, MODE_EMA, PRICE_CLOSE);
    handle_ema_slow = iMA(_Symbol, Timeframe, EMA_slow, 0, MODE_EMA, PRICE_CLOSE);
    handle_macd = iMACD(_Symbol, Timeframe, MACD_fast, MACD_slow, MACD_signal, PRICE_CLOSE);
    
    if(handle_ema_fast == INVALID_HANDLE || handle_ema_slow == INVALID_HANDLE || handle_macd == INVALID_HANDLE)
    {
        Print("Error creating indicators");
        return(INIT_FAILED);
    }
    
    Print("Poseidon EA initialized successfully");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    if(handle_ema_fast != INVALID_HANDLE) IndicatorRelease(handle_ema_fast);
    if(handle_ema_slow != INVALID_HANDLE) IndicatorRelease(handle_ema_slow);
    if(handle_macd != INVALID_HANDLE) IndicatorRelease(handle_macd);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check if it's a new bar
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(_Symbol, Timeframe, 0);
    
    if(current_bar_time == last_bar_time)
        return;
    
    last_bar_time = current_bar_time;
    
    //--- Check trading conditions
    if(!IsTimeToTrade()) return;
    if(!IsMonthAllowed()) return;
    if(trades_today >= MaxTradesPerDay) return;
    
    //--- Update daily trades counter
    UpdateDailyTrades();
    
    //--- Get signals
    signal_score = GetSignalScore();
    
    //--- Execute trades based on signal
    if(signal_score > 0 && !HasOpenPosition(ORDER_TYPE_BUY))
    {
        OpenPosition(ORDER_TYPE_BUY);
    }
    else if(signal_score < 0 && !HasOpenPosition(ORDER_TYPE_SELL))
    {
        OpenPosition(ORDER_TYPE_SELL);
    }
    
    //--- Manage existing positions
    ManagePositions();
}

//+------------------------------------------------------------------+
//| Check if current time is within trading hours                    |
//+------------------------------------------------------------------+
bool IsTimeToTrade()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    int current_hour = dt.hour;
    
    return (current_hour >= StartHour && current_hour < EndHour);
}

//+------------------------------------------------------------------+
//| Check if current month is allowed for trading                    |
//+------------------------------------------------------------------+
bool IsMonthAllowed()
{
    if(!UseMonthFilter) return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    switch(dt.mon)
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
//| Update daily trades counter                                       |
//+------------------------------------------------------------------+
void UpdateDailyTrades()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    datetime today = StructToTime(dt);
    dt.hour = 0;
    dt.min = 0;
    dt.sec = 0;
    today = StructToTime(dt);
    
    if(last_trade_date != today)
    {
        trades_today = 0;
        last_trade_date = today;
    }
}

//+------------------------------------------------------------------+
//| Get signal score based on multiple conditions                    |
//+------------------------------------------------------------------+
double GetSignalScore()
{
    double score = 0;
    
    //--- Get indicator values
    double ema_fast[], ema_slow[], macd_main[], macd_signal[];
    
    ArraySetAsSeries(ema_fast, true);
    ArraySetAsSeries(ema_slow, true);
    ArraySetAsSeries(macd_main, true);
    ArraySetAsSeries(macd_signal, true);
    
    if(CopyBuffer(handle_ema_fast, 0, 0, 3, ema_fast) < 3 ||
       CopyBuffer(handle_ema_slow, 0, 0, 3, ema_slow) < 3 ||
       CopyBuffer(handle_macd, 0, 0, 3, macd_main) < 3 ||
       CopyBuffer(handle_macd, 1, 0, 3, macd_signal) < 3)
    {
        return 0;
    }
    
    //--- EMA crossover signals
    if(ema_fast[1] > ema_slow[1] && ema_fast[2] <= ema_slow[2])
        score += 1; // Bullish EMA cross
    else if(ema_fast[1] < ema_slow[1] && ema_fast[2] >= ema_slow[2])
        score -= 1; // Bearish EMA cross
    
    //--- MACD signals
    if(macd_main[1] > macd_signal[1] && macd_main[2] <= macd_signal[2])
        score += 1; // Bullish MACD cross
    else if(macd_main[1] < macd_signal[1] && macd_main[2] >= macd_signal[2])
        score -= 1; // Bearish MACD cross
    
    //--- Price position relative to EMAs
    double close_price = iClose(_Symbol, Timeframe, 1);
    if(close_price > ema_fast[1] && close_price > ema_slow[1])
        score += 0.5; // Price above both EMAs
    else if(close_price < ema_fast[1] && close_price < ema_slow[1])
        score -= 0.5; // Price below both EMAs
    
    //--- MACD histogram direction
    if(macd_main[1] > 0 && macd_main[1] > macd_main[2])
        score += 0.5; // Positive and increasing MACD
    else if(macd_main[1] < 0 && macd_main[1] < macd_main[2])
        score -= 0.5; // Negative and decreasing MACD
    
    return score;
}

//+------------------------------------------------------------------+
//| Check if there's an open position of the specified type          |
//+------------------------------------------------------------------+
bool HasOpenPosition(ENUM_ORDER_TYPE order_type)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if((order_type == ORDER_TYPE_BUY && pos_type == POSITION_TYPE_BUY) ||
               (order_type == ORDER_TYPE_SELL && pos_type == POSITION_TYPE_SELL))
            {
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Open a new position                                              |
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE order_type)
{
    double lot_size = CalculateLotSize();
    if(lot_size <= 0) return;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    double price = (order_type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = lot_size;
    request.type = order_type;
    request.price = price;
    request.deviation = 10;
    request.magic = 12345;
    request.comment = "Poseidon EA";
    
    if(OrderSend(request, result))
    {
        Print("Position opened: ", EnumToString(order_type), " Volume: ", lot_size);
        trades_today++;
    }
    else
    {
        Print("Error opening position: ", result.retcode);
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk management                      |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double lot_size = 0;
    double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(UseFixedRisk)
    {
        double risk_amount = account_balance * FixedRisk / 100.0;
        
        // Adjust for loss streak
        if(UseStreakRiskReduction && loss_streak >= StreakLength)
        {
            risk_amount *= StreakRiskReduction;
        }
        
        // Calculate lot size based on risk (simplified calculation)
        double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double stop_loss_pips = 100; // Default stop loss in pips
        
        if(pip_value > 0 && stop_loss_pips > 0)
        {
            lot_size = risk_amount / (stop_loss_pips * pip_value);
        }
    }
    else
    {
        double risk_amount = FixedMoney;
        
        // Adjust for loss streak
        if(UseStreakRiskReduction && loss_streak >= StreakLength)
        {
            risk_amount *= StreakRiskReduction;
        }
        
        // Calculate lot size based on fixed money risk
        double pip_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double stop_loss_pips = 100; // Default stop loss in pips
        
        if(pip_value > 0 && stop_loss_pips > 0)
        {
            lot_size = risk_amount / (stop_loss_pips * pip_value);
        }
    }
    
    // Normalize lot size
    lot_size = MathFloor(lot_size / lot_step) * lot_step;
    lot_size = MathMax(min_lot, MathMin(max_lot, lot_size));
    
    return lot_size;
}

//+------------------------------------------------------------------+
//| Manage existing positions                                         |
//+------------------------------------------------------------------+
void ManagePositions()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetSymbol(i) == _Symbol)
        {
            ulong ticket = PositionGetInteger(POSITION_TICKET);
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                                   SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double profit_points = 0;
            
            if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                profit_points = (current_price - open_price) / _Point;
            }
            else
            {
                profit_points = (open_price - current_price) / _Point;
            }
            
            // Break-even management
            if(UseBE && profit_points >= BEPoints)
            {
                double sl = PositionGetDouble(POSITION_SL);
                if((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY && sl < open_price) ||
                   (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL && sl > open_price) || sl == 0)
                {
                    MoveToBreakEven(ticket, open_price);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Move stop loss to break-even                                     |
//+------------------------------------------------------------------+
void MoveToBreakEven(ulong ticket, double open_price)
{
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_SLTP;
    request.position = ticket;
    request.sl = open_price;
    request.tp = PositionGetDouble(POSITION_TP);
    
    if(OrderSend(request, result))
    {
        Print("Position moved to break-even: ", ticket);
    }
}

//+------------------------------------------------------------------+
//| Handle trade events                                               |
//+------------------------------------------------------------------+
void OnTrade()
{
    // Update loss streak counter
    HistorySelect(TimeCurrent() - 86400, TimeCurrent()); // Last 24 hours
    
    int consecutive_losses = 0;
    for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
        {
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            if(profit < 0)
            {
                consecutive_losses++;
            }
            else if(profit > 0)
            {
                break;
            }
        }
    }
    
    loss_streak = consecutive_losses;
}