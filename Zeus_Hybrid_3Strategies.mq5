//+------------------------------------------------------------------+
//|                                    Zeus_Hybrid_3Strategies.mq5    |
//|                                          Combination de 3 Logiques |
//|                                                                    |
//| Stratégie 1: Daily Range Breakout (DRB)                          |
//| Stratégie 2: Mean Reversion avec ATR                             |
//| Stratégie 3: Adaptive Risk + Trailing Stop                       |
//| Seuil: 7/10 signaux minimum requis                               |
//+------------------------------------------------------------------+
#property copyright "Zeus Trading System"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters UNIQUES
input group "=== FTMO RISK MANAGEMENT ==="
input double InpRiskPerTrade = 0.30;           // Risque par trade (%)
input double InpMaxSimultaneousRisk = 3.0;     // Risque simultané max (%)
input double InpMaxDailyLoss = 3.0;            // Perte quotidienne max (%) - LIMITE DURE
input int    InpMaxPositions = 10;             // Positions simultanées max
// Note: Objectif DD total < 8% (pas une limite, juste un goal de performance)

input group "=== STRATEGY 1: DAILY RANGE BREAKOUT ==="
input int    InpDRB_StartHour = 0;             // Heure début calcul range
input int    InpDRB_EndHour = 6;               // Heure fin calcul range
input int    InpDRB_TradingStartHour = 6;      // Heure début trading
input int    InpDRB_TradingEndHour = 22;       // Heure fin trading
input double InpDRB_RiskReward = 5.0;          // Risk:Reward ratio (1:5)
input double InpDRB_BreakoutBuffer = 5.0;      // Buffer breakout (points)
input bool   InpDRB_RequirePullback = true;    // Exiger pullback après breakout

input group "=== STRATEGY 2: MEAN REVERSION ATR ==="
input int    InpMR_EMAPeriod = 200;            // Période EMA
input int    InpMR_ATRPeriod = 14;             // Période ATR
input double InpMR_ATRMultiplier = 2.0;        // Multiplicateur ATR
input double InpMR_MinATR = 0.0001;            // ATR minimum
input double InpMR_ATRAdaptiveMin = 1.5;       // ATR adaptatif Min
input double InpMR_ATRAdaptiveMax = 3.0;       // ATR adaptatif Max

input group "=== SIGNAUX TECHNIQUES ==="
input int    InpRSI_Period = 14;               // Période RSI
input int    InpRSI_Overbought = 70;           // RSI surachat
input int    InpRSI_Oversold = 30;             // RSI survente
input int    InpMACD_Fast = 12;                // MACD Fast EMA
input int    InpMACD_Slow = 26;                // MACD Slow EMA
input int    InpMACD_Signal = 9;               // MACD Signal

input group "=== STRATEGY 3: ADAPTIVE TRAILING STOP ==="
input double InpTS_Phase1_Profit = 0.5;        // Phase 1: % profit pour BE
input double InpTS_Phase2_Profit = 1.5;        // Phase 2: % profit pour trailing +0.5%
input double InpTS_Phase3_Profit = 3.0;        // Phase 3: % profit pour trailing +1.5%
input double InpTS_ATRMultiplier = 2.0;        // Multiplicateur ATR pour distance

input group "=== CORRELATION & EXPOSURE ==="
input double InpMaxCorrelation = 0.85;         // Corrélation max autorisée - OPTIMISER: 0.75-0.90 (step 0.05)
input int    InpCorrelationPeriod = 100;       // Période calcul corrélation
input ENUM_TIMEFRAMES InpCorrelationTF = PERIOD_H1; // Timeframe corrélation

input group "=== VOLATILITY REGIME (Amélioration #1) ==="
input bool   InpVolRegime_Enabled = true;      // Activer détection volatilité
input int    InpVolRegime_Period = 100;        // Période calcul percentile ATR
input double InpVolRegime_LowThreshold = 30.0; // Seuil Low (percentile)
input double InpVolRegime_HighThreshold = 70.0;// Seuil High (percentile)
input double InpVolRegime_ExtremeThreshold = 95.0; // Seuil Extreme (skip trades) - OPTIMISER: 90-99

input group "=== TIME-BASED FILTERS (Amélioration #2) ==="
input bool   InpTimeFilter_Enabled = true;     // Activer filtres horaires
input bool   InpTimeFilter_AvoidLunchTime = false; // Éviter 12h-14h (low volume) - OPTIMISER: true/false
input bool   InpTimeFilter_AvoidAsianNight = true; // Éviter 22h-2h (flat) - OPTIMISER: true/false

input group "=== EQUITY CURVE MONITORING (Amélioration #6) ==="
input bool   InpEquityCurve_Enabled = false;   // Activer monitoring equity curve - DÉSACTIVÉ pour backtest
input int    InpEquityCurve_LookbackTrades = 20; // Trades pour calcul slope
input int    InpEquityCurve_PauseDaysNegSlope = 1; // Pause si slope négatif (jours) - OPTIMISER: 1-3
input int    InpEquityCurve_PauseDaysLosingStreak = 1; // Pause si 10 pertes (jours)

input group "=== MARKET REGIME ADX (Amélioration #7) ==="
input bool   InpADX_Enabled = true;            // Activer détection ADX
input int    InpADX_Period = 14;               // Période ADX
input double InpADX_TrendingThreshold = 25.0;  // ADX > 25 = Trending
input double InpADX_RangingThreshold = 20.0;   // ADX < 20 = Ranging

input group "=== ML SIGNAL STRENGTH (Amélioration #9) ==="
input bool   InpML_Enabled = true;             // Activer ML tracking signaux
input int    InpML_RecalibrationTrades = 100;  // Recalibrer tous les X trades

input group "=== NEWS FILTER (Amélioration #10) ==="
input bool   InpNews_Enabled = false;          // Activer filtre news - DÉSACTIVÉ pour backtest (pas de données historiques)
input int    InpNews_PauseBeforeMinutes = 10;  // Pause avant news (minutes) - OPTIMISER: 5-15
input int    InpNews_PauseAfterMinutes = 20;   // Pause après news (minutes) - OPTIMISER: 15-30
input int    InpNews_MinImportance = 3;        // Importance min (1=Low, 2=Medium, 3=High) - OPTIMISER: 2-3
input int    InpNews_UpdateIntervalHours = 6;  // Update news cache (heures)

input group "=== SCORING SIGNALS ==="
input int    InpMinSignalsRequired = 6;        // Signaux minimum requis - OPTIMISER: 5-8 (step 1)

input group "=== GENERAL SETTINGS ==="
input int    InpMagicNumber = 789456;          // Magic Number
input string InpTradeComment = "Zeus_Hybrid";  // Commentaire trades
input bool   InpVerboseLogs = true;            // Logs détaillés
input double InpMaxSpreadATR = 2.0;            // Spread max en ATR
input bool   InpPartialExit = true;            // Sorties partielles activées
input double InpPartialExitPercent = 50.0;     // % position à clôturer (TP1)

//--- Currency pairs
string g_Symbols[] = {"EURUSD", "GBPUSD", "USDJPY", "USDCHF", "AUDUSD", "NZDUSD", "USDCAD"};

//--- Global variables
CTrade g_Trade;
datetime g_LastBarTime = 0;
datetime g_DailyResetTime = 0;
double g_DailyPnL = 0.0;
double g_DailyStartBalance = 0.0;
double g_InitialBalance = 0.0;
double g_PeakBalance = 0.0;
int g_ConsecutiveLosses = 0;
int g_ConsecutiveWins = 0;

//--- Amélioration #6: Equity Curve
double g_EquityCurve[];
int g_EquityCurveIndex = 0;
datetime g_PauseUntilTime = 0;

//--- Amélioration #9: ML Signal Strength
int g_SignalCorrect[10];    // Compteur signaux corrects
int g_SignalTotal[10];      // Compteur signaux totaux
double g_SignalWeight[10];  // Poids adaptatifs

//--- Amélioration #8: Correlation Matrix
string g_OpenedCurrencies[];
int g_CurrencyCount[];

//--- Amélioration #10: News Cache
struct NewsEvent {
    datetime time;
    string currency;
    string title;
    int importance;  // 1=Low, 2=Medium, 3=High
};
NewsEvent g_NewsEvents[];
datetime g_NewsLastUpdate = 0;

//--- Indicator handles
int g_EMA_Handle[];
int g_ATR_Handle[];
int g_RSI_Handle[];
int g_MACD_Handle[];
int g_ADX_Handle[];  // Amélioration #7

//--- Structures
struct DailyRangeData {
    double highPrice;
    double lowPrice;
    double rangeSize;
    datetime calculatedDate;
    bool isValid;
};

struct PositionData {
    ulong ticket;
    string symbol;
    double entryPrice;
    double initialRisk;
    double currentProfit;
    double currentProfitPercent;
};

//--- Daily range cache
DailyRangeData g_DailyRange[];

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("===== ZEUS HYBRID 3 STRATEGIES - INITIALISATION =====");

    g_Trade.SetExpertMagicNumber(InpMagicNumber);
    g_Trade.SetDeviationInPoints(20);
    g_Trade.SetTypeFilling(ORDER_FILLING_FOK);
    g_Trade.SetAsyncMode(false);

    //--- Initialize arrays
    ArrayResize(g_EMA_Handle, ArraySize(g_Symbols));
    ArrayResize(g_ATR_Handle, ArraySize(g_Symbols));
    ArrayResize(g_RSI_Handle, ArraySize(g_Symbols));
    ArrayResize(g_MACD_Handle, ArraySize(g_Symbols));
    ArrayResize(g_ADX_Handle, ArraySize(g_Symbols));
    ArrayResize(g_DailyRange, ArraySize(g_Symbols));

    //--- Initialize Equity Curve
    if(InpEquityCurve_Enabled)
    {
        ArrayResize(g_EquityCurve, InpEquityCurve_LookbackTrades);
        ArrayInitialize(g_EquityCurve, 0);
    }

    //--- Initialize ML Signal Weights
    if(InpML_Enabled)
    {
        ArrayInitialize(g_SignalCorrect, 0);
        ArrayInitialize(g_SignalTotal, 0);
        ArrayInitialize(g_SignalWeight, 1.0); // Poids initial = 1.0
    }

    //--- Create indicator handles for all symbols
    for(int i = 0; i < ArraySize(g_Symbols); i++)
    {
        g_EMA_Handle[i] = iMA(g_Symbols[i], PERIOD_CURRENT, InpMR_EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
        g_ATR_Handle[i] = iATR(g_Symbols[i], PERIOD_CURRENT, InpMR_ATRPeriod);
        g_RSI_Handle[i] = iRSI(g_Symbols[i], PERIOD_CURRENT, InpRSI_Period, PRICE_CLOSE);
        g_MACD_Handle[i] = iMACD(g_Symbols[i], PERIOD_CURRENT, InpMACD_Fast, InpMACD_Slow, InpMACD_Signal, PRICE_CLOSE);
        if(InpADX_Enabled)
            g_ADX_Handle[i] = iADX(g_Symbols[i], PERIOD_CURRENT, InpADX_Period);

        bool handlesOK = (g_EMA_Handle[i] != INVALID_HANDLE && g_ATR_Handle[i] != INVALID_HANDLE &&
                          g_RSI_Handle[i] != INVALID_HANDLE && g_MACD_Handle[i] != INVALID_HANDLE);

        if(InpADX_Enabled)
            handlesOK = handlesOK && (g_ADX_Handle[i] != INVALID_HANDLE);

        if(!handlesOK)
        {
            Print("ERREUR: Impossible de créer les indicateurs pour ", g_Symbols[i]);
            return INIT_FAILED;
        }

        //--- Initialize daily range
        g_DailyRange[i].isValid = false;
        g_DailyRange[i].calculatedDate = 0;
    }

    //--- Initialize balance tracking
    g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DailyStartBalance = g_InitialBalance;
    g_PeakBalance = g_InitialBalance;
    g_DailyResetTime = TimeCurrent();

    Print("Initialisation réussie - Balance: ", g_InitialBalance);
    Print("Paires surveillées: ", ArraySize(g_Symbols));
    Print("Seuil validation: 7/10 signaux minimum");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Release indicator handles
    for(int i = 0; i < ArraySize(g_Symbols); i++)
    {
        if(g_EMA_Handle[i] != INVALID_HANDLE) IndicatorRelease(g_EMA_Handle[i]);
        if(g_ATR_Handle[i] != INVALID_HANDLE) IndicatorRelease(g_ATR_Handle[i]);
        if(g_RSI_Handle[i] != INVALID_HANDLE) IndicatorRelease(g_RSI_Handle[i]);
        if(g_MACD_Handle[i] != INVALID_HANDLE) IndicatorRelease(g_MACD_Handle[i]);
    }

    Print("Zeus Hybrid déchargé - Raison: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    //--- Check new bar
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime == g_LastBarTime) return;
    g_LastBarTime = currentBarTime;

    //--- Daily reset
    CheckDailyReset();

    //--- TOUJOURS update trailing stops (même si daily loss atteint)
    UpdateAllTrailingStops();

    //--- FTMO checks pour NOUVEAUX trades seulement
    if(!CheckFTMOLimits())
    {
        if(InpVerboseLogs) Print("FTMO Limits atteintes - Pas de nouveaux trades, positions existantes maintenues");
        return; // Bloque nouveaux trades mais trailing continue
    }

    //--- Scan all symbols for trading opportunities
    for(int i = 0; i < ArraySize(g_Symbols); i++)
    {
        AnalyzeSymbol(g_Symbols[i], i);
    }
}

//+------------------------------------------------------------------+
//| Analyze symbol for trading opportunity                           |
//+------------------------------------------------------------------+
void AnalyzeSymbol(string symbol, int symbolIndex)
{
    //--- FILTRES ÉLIMINATOIRES (doivent TOUS être respectés)

    //--- Filtre 1: Pas de position déjà ouverte
    if(HasOpenPosition(symbol)) return;

    //--- Filtre 2: Vérifier heures de trading
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.hour < InpDRB_TradingStartHour || dt.hour >= InpDRB_TradingEndHour)
    {
        if(InpVerboseLogs) Print("Filtre HEURES échoué: ", symbol);
        return;
    }

    //--- Filtre 2b: Time-Based Session Filter (Amélioration #2)
    if(!CheckTimeFilter()) return;

    //--- Filtre 2c: Equity Curve Pause (Amélioration #6)
    if(!CheckEquityPause()) return;

    //--- Filtre 2d: News Filter (Amélioration #10)
    if(!CheckNewsFilter()) return;

    //--- Filtre 3: Corrélation
    if(!CheckCorrelationExposure(symbol))
    {
        if(InpVerboseLogs) Print("Filtre CORRELATION échoué: ", symbol);
        return;
    }

    //--- Filtre 3b: Currency Diversification (Amélioration #8)
    if(!CheckCurrencyDiversification(symbol))
    {
        return;
    }

    //--- Update daily range
    UpdateDailyRange(symbol, symbolIndex);

    //--- Get market data
    double close = iClose(symbol, PERIOD_CURRENT, 1);
    double open = iOpen(symbol, PERIOD_CURRENT, 1);
    double high = iHigh(symbol, PERIOD_CURRENT, 1);
    double low = iLow(symbol, PERIOD_CURRENT, 1);

    //--- Get indicator values
    double ema[], atr[], rsi[], macd_main[], macd_signal[];
    ArraySetAsSeries(ema, true);
    ArraySetAsSeries(atr, true);
    ArraySetAsSeries(rsi, true);
    ArraySetAsSeries(macd_main, true);
    ArraySetAsSeries(macd_signal, true);

    if(CopyBuffer(g_EMA_Handle[symbolIndex], 0, 0, 3, ema) < 3) return;
    if(CopyBuffer(g_ATR_Handle[symbolIndex], 0, 0, 3, atr) < 3) return;
    if(CopyBuffer(g_RSI_Handle[symbolIndex], 0, 0, 3, rsi) < 3) return;
    if(CopyBuffer(g_MACD_Handle[symbolIndex], 0, 0, 3, macd_main) < 3) return;
    if(CopyBuffer(g_MACD_Handle[symbolIndex], 1, 0, 3, macd_signal) < 3) return;

    double currentATR = atr[1];
    double currentEMA = ema[1];
    double currentRSI = rsi[1];
    double currentMACD_Main = macd_main[1];
    double currentMACD_Signal = macd_signal[1];

    //--- Filtre 4: ATR minimum
    if(currentATR < InpMR_MinATR)
    {
        if(InpVerboseLogs) Print("Filtre ATR MIN échoué: ", symbol, " ATR=", currentATR);
        return;
    }

    //--- Filtre 4b: Spread check
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double spread = ask - bid;
    double maxSpread = currentATR * InpMaxSpreadATR;

    if(spread > maxSpread)
    {
        if(InpVerboseLogs) Print("Filtre SPREAD échoué: ", symbol, " Spread=", spread, " Max=", maxSpread);
        return;
    }

    //--- Filtre 5: Daily Loss sous contrôle (80% du max quotidien)
    double dailyLossPercent = (g_DailyPnL / g_DailyStartBalance) * 100.0;
    if(dailyLossPercent <= -(InpMaxDailyLoss * 0.8)) // -2.4% si max = 3%
    {
        if(InpVerboseLogs) Print("Filtre DAILY LOSS échoué: ", symbol, " Daily P&L: ", DoubleToString(dailyLossPercent, 2), "%");
        return;
    }

    //--- Filtre 6: Range valide
    if(!g_DailyRange[symbolIndex].isValid)
    {
        if(InpVerboseLogs) Print("Filtre DAILY RANGE invalide: ", symbol);
        return;
    }

    //--- Amélioration #1: Volatility Regime Detection
    string volRegime = CalculateVolatilityRegime(symbolIndex);
    if(volRegime == "EXTREME")
    {
        if(InpVerboseLogs) Print("Filtre VOL REGIME: EXTREME (>90 percentile) - Skip trade");
        return;
    }

    //--- Amélioration #7: Market Regime Detection (ADX)
    string marketRegime = DetectMarketRegime(symbolIndex);

    if(InpVerboseLogs) Print(">>> ", symbol, " - TOUS FILTRES PASSÉS - Vol:", volRegime, " Market:", marketRegime);

    //--- SIGNAUX POUR SCORING 70% (10 signaux techniques)
    int signalsTotal = 10;
    int signalsBuy = 0, signalsSell = 0;

    //--- Signal 1: Daily Range Breakout (Stratégie 1) avec confirmation pullback
    double highBreakout = g_DailyRange[symbolIndex].highPrice + InpDRB_BreakoutBuffer * _Point;
    double lowBreakout = g_DailyRange[symbolIndex].lowPrice - InpDRB_BreakoutBuffer * _Point;

    bool bullishBreakout = false;
    bool bearishBreakout = false;

    if(InpDRB_RequirePullback)
    {
        // Breakout haussier avec pullback: prix a cassé, puis pullback vers le niveau
        if(high > highBreakout && close < high && close > highBreakout - (currentATR * 0.5))
            bullishBreakout = true;
        // Breakout baissier avec pullback
        if(low < lowBreakout && close > low && close < lowBreakout + (currentATR * 0.5))
            bearishBreakout = true;
    }
    else
    {
        if(close > highBreakout) bullishBreakout = true;
        if(close < lowBreakout) bearishBreakout = true;
    }

    if(bullishBreakout) signalsBuy++;
    else if(bearishBreakout) signalsSell++;

    //--- Signal 2: Mean Reversion ATR adaptatif (Stratégie 2)
    // Calculer ATR adaptatif basé sur la volatilité récente
    double atrAdaptiveMultiplier = InpMR_ATRMultiplier;
    if(atr[1] > atr[2] && atr[2] > atr[3])
    {
        // Volatilité croissante = élargir les bandes
        atrAdaptiveMultiplier = InpMR_ATRAdaptiveMax;
    }
    else if(atr[1] < atr[2] && atr[2] < atr[3])
    {
        // Volatilité décroissante = resserrer les bandes
        atrAdaptiveMultiplier = InpMR_ATRAdaptiveMin;
    }

    double upperBand = currentEMA + (currentATR * atrAdaptiveMultiplier);
    double lowerBand = currentEMA - (currentATR * atrAdaptiveMultiplier);

    if(close < lowerBand) signalsBuy++;      // Prix bas = buy mean reversion
    else if(close > upperBand) signalsSell++; // Prix haut = sell mean reversion

    //--- Signal 3: EMA Trend
    if(ema[1] > ema[2]) signalsBuy++;
    else if(ema[1] < ema[2]) signalsSell++;

    //--- Signal 4: Price vs EMA
    if(close > currentEMA) signalsBuy++;
    else if(close < currentEMA) signalsSell++;

    //--- Signal 5: RSI
    if(currentRSI < InpRSI_Oversold) signalsBuy++;       // RSI survente = buy
    else if(currentRSI > InpRSI_Overbought) signalsSell++; // RSI surachat = sell

    //--- Signal 6: MACD Crossover
    if(currentMACD_Main > currentMACD_Signal && macd_main[2] <= macd_signal[2]) signalsBuy++;  // Bullish cross
    else if(currentMACD_Main < currentMACD_Signal && macd_main[2] >= macd_signal[2]) signalsSell++; // Bearish cross

    //--- Signal 7: MACD Position vs Zero
    if(currentMACD_Main > 0) signalsBuy++;
    else if(currentMACD_Main < 0) signalsSell++;

    //--- Signal 8: Candle Type
    double candleBody = MathAbs(close - open);
    double candleRange = high - low;
    bool bullishCandle = (close > open && candleBody > candleRange * 0.6); // 60% body
    bool bearishCandle = (close < open && candleBody > candleRange * 0.6);

    if(bullishCandle) signalsBuy++;
    else if(bearishCandle) signalsSell++;

    //--- Signal 9: ATR Trend (volatilité)
    if(atr[1] > atr[2]) signalsBuy++;  // Volatilité hausse = momentum
    else if(atr[1] < atr[2]) signalsSell++; // Volatilité baisse = retournement

    //--- Signal 10: Range Momentum
    double rangeCenter = (g_DailyRange[symbolIndex].highPrice + g_DailyRange[symbolIndex].lowPrice) / 2.0;
    if(close > rangeCenter) signalsBuy++;
    else if(close < rangeCenter) signalsSell++;

    //--- EVALUATE THRESHOLD (configurable via InpMinSignalsRequired)
    if(InpVerboseLogs)
    {
        Print("=== ", symbol, " === Signaux BUY: ", signalsBuy, "/", signalsTotal,
              " | SELL: ", signalsSell, "/", signalsTotal);
    }

    //--- Execute trade si >= seuil signaux avec position sizing adaptatif
    if(signalsBuy >= InpMinSignalsRequired)
    {
        Print(">>> SIGNAL BUY validé - ", symbol, " avec ", signalsBuy, "/", signalsTotal, " signaux");
        OpenPosition(symbol, ORDER_TYPE_BUY, currentATR, close, atrAdaptiveMultiplier, volRegime);
    }
    else if(signalsSell >= InpMinSignalsRequired)
    {
        Print(">>> SIGNAL SELL validé - ", symbol, " avec ", signalsSell, "/", signalsTotal, " signaux");
        OpenPosition(symbol, ORDER_TYPE_SELL, currentATR, close, atrAdaptiveMultiplier, volRegime);
    }
    else
    {
        if(InpVerboseLogs) Print("Seuil ", InpMinSignalsRequired, "/", signalsTotal, " non atteint pour ", symbol);
    }
}

//+------------------------------------------------------------------+
//| Open position with risk management                               |
//+------------------------------------------------------------------+
void OpenPosition(string symbol, ENUM_ORDER_TYPE orderType, double atr, double price, double atrMultiplier, string volRegime)
{
    //--- Position sizing adaptatif selon losing streak
    double riskPercent = InpRiskPerTrade;
    if(g_ConsecutiveLosses >= 3)
    {
        riskPercent = InpRiskPerTrade * 0.5; // Réduire risque de 50% après 3 pertes
        if(InpVerboseLogs) Print("Risque réduit à ", riskPercent, "% (losing streak: ", g_ConsecutiveLosses, ")");
    }

    //--- Amélioration #1: Adjust risk based on volatility regime
    riskPercent = GetVolatilityAdjustedRisk(volRegime, riskPercent);
    if(riskPercent == 0.0)
    {
        Print("Vol regime EXTREME - Trade skipped");
        return;
    }

    if(InpVerboseLogs) Print("Risk adjusted for ", volRegime, " regime: ", DoubleToString(riskPercent, 3), "%");

    double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * (riskPercent / 100.0);

    //--- Calculate SL/TP based on ATR adaptatif
    double slDistance = atr * atrMultiplier;
    double tpDistance = slDistance * InpDRB_RiskReward;

    double sl = 0, tp = 0, tp1 = 0;

    if(orderType == ORDER_TYPE_BUY)
    {
        sl = price - slDistance;
        tp = price + tpDistance;
        tp1 = price + (tpDistance * 0.3); // TP1 à 30% du chemin (1:1.5 environ)
    }
    else if(orderType == ORDER_TYPE_SELL)
    {
        sl = price + slDistance;
        tp = price - tpDistance;
        tp1 = price - (tpDistance * 0.3); // TP1 à 30% du chemin
    }

    //--- Calculate lot size
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double slPoints = MathAbs(price - sl);

    double lotSize = (riskAmount / (slPoints / tickSize * tickValue));

    //--- Normalize lot size
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

    //--- Execute order avec sorties partielles
    bool result = false;

    if(InpPartialExit)
    {
        // Ouvrir 2 positions pour permettre sortie partielle
        double lot1 = lotSize * (InpPartialExitPercent / 100.0);
        double lot2 = lotSize - lot1;

        lot1 = MathFloor(lot1 / lotStep) * lotStep;
        lot2 = MathFloor(lot2 / lotStep) * lotStep;

        if(lot1 >= minLot && lot2 >= minLot)
        {
            // Position 1: TP rapproché (30% du chemin)
            if(orderType == ORDER_TYPE_BUY)
                result = g_Trade.Buy(lot1, symbol, 0, sl, tp1, InpTradeComment + "_TP1");
            else
                result = g_Trade.Sell(lot1, symbol, 0, sl, tp1, InpTradeComment + "_TP1");

            // Position 2: TP final
            if(result)
            {
                if(orderType == ORDER_TYPE_BUY)
                    g_Trade.Buy(lot2, symbol, 0, sl, tp, InpTradeComment + "_TP2");
                else
                    g_Trade.Sell(lot2, symbol, 0, sl, tp, InpTradeComment + "_TP2");

                Print(">>> ORDRES OUVERTS (Partial Exit): ", symbol, " | Type: ", EnumToString(orderType),
                      " | Lot1: ", lot1, " (TP1: ", tp1, ") | Lot2: ", lot2, " (TP2: ", tp, ") | SL: ", sl);
            }
        }
        else
        {
            // Lot trop petit pour split, position unique
            if(orderType == ORDER_TYPE_BUY)
                result = g_Trade.Buy(lotSize, symbol, 0, sl, tp, InpTradeComment);
            else
                result = g_Trade.Sell(lotSize, symbol, 0, sl, tp, InpTradeComment);

            if(result)
            {
                Print(">>> ORDRE OUVERT: ", symbol, " | Type: ", EnumToString(orderType),
                      " | Lot: ", lotSize, " | SL: ", sl, " | TP: ", tp);
            }
        }
    }
    else
    {
        // Pas de sortie partielle
        if(orderType == ORDER_TYPE_BUY)
            result = g_Trade.Buy(lotSize, symbol, 0, sl, tp, InpTradeComment);
        else
            result = g_Trade.Sell(lotSize, symbol, 0, sl, tp, InpTradeComment);

        if(result)
        {
            Print(">>> ORDRE OUVERT: ", symbol, " | Type: ", EnumToString(orderType),
                  " | Lot: ", lotSize, " | SL: ", sl, " | TP: ", tp);
        }
    }

    if(!result)
    {
        Print("ERREUR ouverture ordre: ", symbol, " - ", g_Trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Update daily range for symbol                                    |
//+------------------------------------------------------------------+
void UpdateDailyRange(string symbol, int symbolIndex)
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    datetime today = StringToTime(IntegerToString(dt.year) + "." +
                                   IntegerToString(dt.mon) + "." +
                                   IntegerToString(dt.day) + " 00:00");

    //--- Check if already calculated for today
    if(g_DailyRange[symbolIndex].calculatedDate == today && g_DailyRange[symbolIndex].isValid)
        return;

    //--- Calculate range only after end hour
    if(dt.hour < InpDRB_EndHour)
    {
        g_DailyRange[symbolIndex].isValid = false;
        return;
    }

    //--- Find high and low between start and end hours
    datetime startTime = StringToTime(IntegerToString(dt.year) + "." +
                                       IntegerToString(dt.mon) + "." +
                                       IntegerToString(dt.day) + " " +
                                       IntegerToString(InpDRB_StartHour) + ":00");

    datetime endTime = StringToTime(IntegerToString(dt.year) + "." +
                                     IntegerToString(dt.mon) + "." +
                                     IntegerToString(dt.day) + " " +
                                     IntegerToString(InpDRB_EndHour) + ":00");

    int startBar = iBarShift(symbol, PERIOD_H1, startTime);
    int endBar = iBarShift(symbol, PERIOD_H1, endTime);

    if(startBar < 0 || endBar < 0) return;

    double rangeHigh = iHigh(symbol, PERIOD_H1, iHighest(symbol, PERIOD_H1, MODE_HIGH, startBar - endBar, endBar));
    double rangeLow = iLow(symbol, PERIOD_H1, iLowest(symbol, PERIOD_H1, MODE_LOW, startBar - endBar, endBar));

    g_DailyRange[symbolIndex].highPrice = rangeHigh;
    g_DailyRange[symbolIndex].lowPrice = rangeLow;
    g_DailyRange[symbolIndex].rangeSize = rangeHigh - rangeLow;
    g_DailyRange[symbolIndex].calculatedDate = today;
    g_DailyRange[symbolIndex].isValid = true;

    if(InpVerboseLogs)
    {
        Print("Daily Range calculé pour ", symbol, ": High=", rangeHigh, " Low=", rangeLow,
              " Size=", g_DailyRange[symbolIndex].rangeSize);
    }
}

//+------------------------------------------------------------------+
//| Update trailing stops for all positions (Stratégie 3)           |
//+------------------------------------------------------------------+
void UpdateAllTrailingStops()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;

        if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        string symbol = PositionGetString(POSITION_SYMBOL);
        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double currentSL = PositionGetDouble(POSITION_SL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        //--- Calculate profit percentage
        double profitPercent = 0;
        if(posType == POSITION_TYPE_BUY)
        {
            profitPercent = ((currentPrice - entryPrice) / entryPrice) * 100.0;
        }
        else if(posType == POSITION_TYPE_SELL)
        {
            profitPercent = ((entryPrice - currentPrice) / entryPrice) * 100.0;
        }

        //--- Get ATR for this symbol
        int symbolIndex = GetSymbolIndex(symbol);
        if(symbolIndex < 0) continue;

        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(g_ATR_Handle[symbolIndex], 0, 0, 2, atr) < 2) continue;

        double atrDistance = atr[1] * InpTS_ATRMultiplier;
        double newSL = currentSL;

        //--- Phase 1: +0.5% profit → SL to Breakeven
        if(profitPercent >= InpTS_Phase1_Profit && currentSL != entryPrice)
        {
            newSL = entryPrice;
            if(InpVerboseLogs) Print("Phase 1 - SL à Breakeven: ", symbol);
        }

        //--- Phase 2: +1.5% profit → Trailing to +0.5%
        else if(profitPercent >= InpTS_Phase2_Profit)
        {
            double targetProfit = entryPrice * (InpTS_Phase1_Profit / 100.0);

            if(posType == POSITION_TYPE_BUY)
            {
                newSL = entryPrice + targetProfit;
                if(newSL < currentSL) newSL = currentSL; // Never move SL backwards
            }
            else if(posType == POSITION_TYPE_SELL)
            {
                newSL = entryPrice - targetProfit;
                if(newSL > currentSL) newSL = currentSL;
            }

            if(InpVerboseLogs) Print("Phase 2 - Trailing +0.5%: ", symbol);
        }

        //--- Phase 3: +3% profit → Trailing to +1.5%
        else if(profitPercent >= InpTS_Phase3_Profit)
        {
            double targetProfit = entryPrice * (InpTS_Phase2_Profit / 100.0);

            if(posType == POSITION_TYPE_BUY)
            {
                newSL = entryPrice + targetProfit;
                if(newSL < currentSL) newSL = currentSL;
            }
            else if(posType == POSITION_TYPE_SELL)
            {
                newSL = entryPrice - targetProfit;
                if(newSL > currentSL) newSL = currentSL;
            }

            if(InpVerboseLogs) Print("Phase 3 - Trailing +1.5%: ", symbol);
        }

        //--- Modify SL if changed
        if(newSL != currentSL && newSL > 0)
        {
            double currentTP = PositionGetDouble(POSITION_TP);
            if(g_Trade.PositionModify(ticket, newSL, currentTP))
            {
                Print("Trailing Stop modifié: ", symbol, " | Nouveau SL: ", newSL,
                      " | Profit: ", DoubleToString(profitPercent, 2), "%");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check FTMO limits                                                |
//+------------------------------------------------------------------+
bool CheckFTMOLimits()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    //--- Daily loss check (calculé sur balance début journée) - BLOQUE NOUVEAUX TRADES
    double dailyLossPercent = (g_DailyPnL / g_DailyStartBalance) * 100.0;
    if(dailyLossPercent <= -InpMaxDailyLoss)
    {
        Print("⚠️ DAILY LOSS LIMIT ATTEINT (", DoubleToString(dailyLossPercent, 2), "%) - Nouveaux trades bloqués, positions existantes maintenues");
        return false; // Bloque nouveaux trades, trailing continue
    }

    //--- Drawdown total monitoring (objectif < 8%, pas une limite)
    double currentDD = CalculateCurrentDrawdown();
    if(InpVerboseLogs && currentDD > 5.0)
    {
        Print("INFO: Drawdown total actuel: ", DoubleToString(currentDD, 2), "% (Objectif: < 8%)");
    }

    //--- Max positions check
    int openPositions = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            openPositions++;
    }

    if(openPositions >= InpMaxPositions)
    {
        if(InpVerboseLogs) Print("Max positions atteint: ", openPositions);
        return false;
    }

    //--- Simultaneous risk check
    double totalRisk = CalculateTotalRisk();
    if(totalRisk >= InpMaxSimultaneousRisk)
    {
        if(InpVerboseLogs) Print("Risque simultané max atteint: ", DoubleToString(totalRisk, 2), "%");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calculate current drawdown                                       |
//+------------------------------------------------------------------+
double CalculateCurrentDrawdown()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    if(balance > g_PeakBalance)
        g_PeakBalance = balance;

    double drawdown = ((g_PeakBalance - balance) / g_PeakBalance) * 100.0;

    return MathMax(0, drawdown);
}

//+------------------------------------------------------------------+
//| Calculate total risk from open positions                         |
//+------------------------------------------------------------------+
double CalculateTotalRisk()
{
    double totalRisk = 0.0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            double positionRisk = MathAbs(PositionGetDouble(POSITION_PROFIT));
            totalRisk += (positionRisk / balance) * 100.0;
        }
    }

    return totalRisk;
}

//+------------------------------------------------------------------+
//| Check correlation exposure                                        |
//+------------------------------------------------------------------+
bool CheckCorrelationExposure(string symbol)
{
    //--- Get all open positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) <= 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        string posSymbol = PositionGetString(POSITION_SYMBOL);
        if(posSymbol == symbol) continue;

        //--- Calculate correlation
        double correlation = CalculateCorrelation(symbol, posSymbol, InpCorrelationPeriod, InpCorrelationTF);

        if(MathAbs(correlation) > InpMaxCorrelation)
        {
            if(InpVerboseLogs)
            {
                Print("Corrélation trop élevée entre ", symbol, " et ", posSymbol, ": ",
                      DoubleToString(correlation, 3));
            }
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calculate Pearson correlation between two symbols                |
//+------------------------------------------------------------------+
double CalculateCorrelation(string symbol1, string symbol2, int period, ENUM_TIMEFRAMES tf)
{
    double closes1[], closes2[];
    ArraySetAsSeries(closes1, true);
    ArraySetAsSeries(closes2, true);

    if(CopyClose(symbol1, tf, 0, period, closes1) < period) return 0;
    if(CopyClose(symbol2, tf, 0, period, closes2) < period) return 0;

    //--- Calculate means
    double mean1 = 0, mean2 = 0;
    for(int i = 0; i < period; i++)
    {
        mean1 += closes1[i];
        mean2 += closes2[i];
    }
    mean1 /= period;
    mean2 /= period;

    //--- Calculate correlation
    double numerator = 0, denom1 = 0, denom2 = 0;
    for(int i = 0; i < period; i++)
    {
        double diff1 = closes1[i] - mean1;
        double diff2 = closes2[i] - mean2;

        numerator += diff1 * diff2;
        denom1 += diff1 * diff1;
        denom2 += diff2 * diff2;
    }

    if(denom1 == 0 || denom2 == 0) return 0;

    return numerator / (MathSqrt(denom1) * MathSqrt(denom2));
}

//+------------------------------------------------------------------+
//| Check if symbol has open position                                |
//+------------------------------------------------------------------+
bool HasOpenPosition(string symbol)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0 &&
           PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
           PositionGetString(POSITION_SYMBOL) == symbol)
        {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get symbol index from array                                      |
//+------------------------------------------------------------------+
int GetSymbolIndex(string symbol)
{
    for(int i = 0; i < ArraySize(g_Symbols); i++)
    {
        if(g_Symbols[i] == symbol) return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Check and reset daily counters                                   |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    datetime today = StringToTime(IntegerToString(dt.year) + "." +
                                   IntegerToString(dt.mon) + "." +
                                   IntegerToString(dt.day) + " 00:00");

    if(today > g_DailyResetTime)
    {
        double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_DailyStartBalance = currentBalance; // Balance début journée
        g_DailyPnL = 0.0;
        g_DailyResetTime = today;

        Print("===== RESET QUOTIDIEN - Nouvelle journée de trading =====");
        Print("Balance début journée: ", g_DailyStartBalance);
    }

    //--- Update daily P&L
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DailyPnL = currentBalance - g_DailyStartBalance; // P&L depuis début journée
}

//+------------------------------------------------------------------+
//| Track wins/losses for adaptive position sizing                   |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        ulong dealTicket = trans.deal;
        if(dealTicket > 0)
        {
            if(HistoryDealSelect(dealTicket))
            {
                long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
                if(dealMagic == InpMagicNumber)
                {
                    long dealEntry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                    if(dealEntry == DEAL_ENTRY_OUT) // Position fermée
                    {
                        double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);

                        if(profit > 0)
                        {
                            g_ConsecutiveWins++;
                            g_ConsecutiveLosses = 0;
                            Print("Trade WIN - Série gagnante: ", g_ConsecutiveWins);
                        }
                        else if(profit < 0)
                        {
                            g_ConsecutiveLosses++;
                            g_ConsecutiveWins = 0;
                            Print("Trade LOSS - Série perdante: ", g_ConsecutiveLosses);
                        }

                        //--- Update Equity Curve (#6)
                        if(InpEquityCurve_Enabled)
                        {
                            UpdateEquityCurve(profit);
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #1: Calculate ATR Volatility Regime                |
//+------------------------------------------------------------------+
string CalculateVolatilityRegime(int symbolIndex)
{
    if(!InpVolRegime_Enabled) return "NORMAL";

    double atr[];
    ArraySetAsSeries(atr, true);

    if(CopyBuffer(g_ATR_Handle[symbolIndex], 0, 0, InpVolRegime_Period, atr) < InpVolRegime_Period)
        return "NORMAL";

    //--- Calculate percentile of current ATR
    double currentATR = atr[0];
    double sorted[];
    ArrayResize(sorted, InpVolRegime_Period);
    ArrayCopy(sorted, atr, 0, 0, InpVolRegime_Period);
    ArraySort(sorted);

    int rank = 0;
    for(int i = 0; i < InpVolRegime_Period; i++)
    {
        if(currentATR >= sorted[i]) rank++;
    }

    double percentile = (double)rank / (double)InpVolRegime_Period * 100.0;

    //--- Classify regime
    if(percentile >= InpVolRegime_ExtremeThreshold)
        return "EXTREME";  // > 90 = Skip trades
    else if(percentile >= InpVolRegime_HighThreshold)
        return "HIGH";     // 70-90 = High volatility
    else if(percentile <= InpVolRegime_LowThreshold)
        return "LOW";      // < 30 = Low volatility
    else
        return "NORMAL";   // 30-70 = Normal
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #1: Adjust Risk Based on Volatility Regime         |
//+------------------------------------------------------------------+
double GetVolatilityAdjustedRisk(string regime, double baseRisk)
{
    if(regime == "EXTREME") return 0.0;       // Skip trades
    if(regime == "HIGH") return baseRisk * 0.67; // Reduce -33%
    if(regime == "LOW") return baseRisk * 1.33;  // Increase +33%
    return baseRisk; // NORMAL
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #2: Time-Based Session Filter                      |
//+------------------------------------------------------------------+
bool CheckTimeFilter()
{
    if(!InpTimeFilter_Enabled) return true;

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    //--- Avoid lunch time (12h-14h GMT) - Low volume
    if(InpTimeFilter_AvoidLunchTime && dt.hour >= 12 && dt.hour < 14)
    {
        if(InpVerboseLogs) Print("Filtre TIME: Lunch time évité (12h-14h)");
        return false;
    }

    //--- Avoid Asian night (22h-2h GMT) - Flat market
    if(InpTimeFilter_AvoidAsianNight && (dt.hour >= 22 || dt.hour < 2))
    {
        if(InpVerboseLogs) Print("Filtre TIME: Asian night évité (22h-2h)");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #6: Update Equity Curve                            |
//+------------------------------------------------------------------+
void UpdateEquityCurve(double profit)
{
    g_EquityCurve[g_EquityCurveIndex] = profit;
    g_EquityCurveIndex = (g_EquityCurveIndex + 1) % InpEquityCurve_LookbackTrades;

    //--- Check if we have enough data
    double sumCheck = 0;
    for(int j = 0; j < InpEquityCurve_LookbackTrades; j++)
        sumCheck += MathAbs(g_EquityCurve[j]);

    if(sumCheck == 0 && g_EquityCurveIndex < 5) return;

    //--- Calculate slope (simple linear regression)
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    int n = 0;

    for(int i = 0; i < InpEquityCurve_LookbackTrades; i++)
    {
        if(g_EquityCurve[i] != 0)
        {
            sumX += n;
            sumY += g_EquityCurve[i];
            sumXY += n * g_EquityCurve[i];
            sumX2 += n * n;
            n++;
        }
    }

    if(n < 10) return; // Pas assez de données

    double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);

    //--- Negative slope = Losing trend → Pause
    if(slope < 0)
    {
        g_PauseUntilTime = TimeCurrent() + InpEquityCurve_PauseDaysNegSlope * 86400;
        Print("⚠️ EQUITY CURVE: Slope négatif détecté (", DoubleToString(slope, 4), ") - Pause ", InpEquityCurve_PauseDaysNegSlope, " jours");
    }

    //--- 10 consecutive losses → Pause
    if(g_ConsecutiveLosses >= 10)
    {
        g_PauseUntilTime = TimeCurrent() + InpEquityCurve_PauseDaysLosingStreak * 86400;
        Print("⚠️ EQUITY CURVE: 10 pertes consécutives - Pause ", InpEquityCurve_PauseDaysLosingStreak, " jour");
    }
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #6: Check if trading is paused                     |
//+------------------------------------------------------------------+
bool CheckEquityPause()
{
    if(!InpEquityCurve_Enabled) return true;

    if(TimeCurrent() < g_PauseUntilTime)
    {
        if(InpVerboseLogs) Print("EQUITY CURVE: Pause active jusqu'à ", TimeToString(g_PauseUntilTime));
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #7: Detect Market Regime (Trending vs Ranging)     |
//+------------------------------------------------------------------+
string DetectMarketRegime(int symbolIndex)
{
    if(!InpADX_Enabled) return "NEUTRAL";

    double adx[];
    ArraySetAsSeries(adx, true);

    if(CopyBuffer(g_ADX_Handle[symbolIndex], 0, 0, 3, adx) < 3)
        return "NEUTRAL";

    double currentADX = adx[0];

    if(currentADX >= InpADX_TrendingThreshold)
        return "TRENDING";  // ADX > 25
    else if(currentADX <= InpADX_RangingThreshold)
        return "RANGING";   // ADX < 20
    else
        return "NEUTRAL";   // 20-25
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #8: Check Currency Diversification                 |
//+------------------------------------------------------------------+
bool CheckCurrencyDiversification(string symbol)
{
    //--- Extract currencies from symbol (ex: EURUSD → EUR, USD)
    string base = StringSubstr(symbol, 0, 3);
    string quote = StringSubstr(symbol, 3, 3);

    int currencyExposure[];
    ArrayResize(currencyExposure, 8);
    ArrayInitialize(currencyExposure, 0);

    string currencies[] = {"EUR", "USD", "GBP", "JPY", "CHF", "AUD", "NZD", "CAD"};

    //--- Count currency exposure in open positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            string posBase = StringSubstr(posSymbol, 0, 3);
            string posQuote = StringSubstr(posSymbol, 3, 3);

            for(int c = 0; c < 8; c++)
            {
                if(posBase == currencies[c] || posQuote == currencies[c])
                    currencyExposure[c]++;
            }
        }
    }

    //--- Check if adding this trade would exceed 40% single currency exposure
    int totalPositions = PositionsTotal();
    if(totalPositions == 0) return true;

    for(int c = 0; c < 8; c++)
    {
        if(base == currencies[c] || quote == currencies[c])
        {
            double exposurePercent = (double)(currencyExposure[c] + 1) / (double)(totalPositions + 1) * 100.0;

            if(exposurePercent > 40.0)
            {
                if(InpVerboseLogs)
                    Print("Filtre CURRENCY DIVERSIFICATION: ", currencies[c], " exposition > 40% (", DoubleToString(exposurePercent, 1), "%)");
                return false;
            }
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #10: Update News Cache (Myfxbook XML)              |
//+------------------------------------------------------------------+
void UpdateNewsCache()
{
    if(!InpNews_Enabled) return;

    //--- Check if update needed
    if(TimeCurrent() - g_NewsLastUpdate < InpNews_UpdateIntervalHours * 3600) return;

    //--- Build Myfxbook XML URL
    datetime now = TimeCurrent();
    datetime tomorrow = now + 86400;

    MqlDateTime dtNow, dtTomorrow;
    TimeToStruct(now, dtNow);
    TimeToStruct(tomorrow, dtTomorrow);

    string startDate = StringFormat("%04d-%02d-%02d 00:00", dtNow.year, dtNow.mon, dtNow.day);
    string endDate = StringFormat("%04d-%02d-%02d 23:59", dtTomorrow.year, dtTomorrow.mon, dtTomorrow.day);

    // Filter: 2-3 = Medium-High importance, major currencies
    string url = "http://www.myfxbook.com/calendar_statement.xml?start=" + startDate +
                 "&end=" + endDate +
                 "&filter=2-3_PEI-USD-EUR-GBP-JPY-CHF-AUD-NZD-CAD&calPeriod=10";

    //--- Fetch XML (WebRequest nécessite URL dans liste autorisée)
    char data[], result[];
    string headers;
    int timeout = 5000;

    ResetLastError();
    int res = WebRequest("GET", url, NULL, NULL, timeout, data, 0, result, headers);

    if(res == -1)
    {
        int error = GetLastError();
        if(error == 4060)
        {
            Print("⚠️ NEWS FILTER: Ajoutez 'www.myfxbook.com' dans Outils > Options > Expert Advisors > WebRequest");
        }
        else
        {
            Print("Erreur WebRequest News: ", error);
        }
        return;
    }

    //--- Parse XML response (simplifié - extraction basique)
    string xmlResponse = CharArrayToString(result);

    //--- Simple parsing: chercher <event> tags
    ArrayResize(g_NewsEvents, 0);

    int pos = 0;
    while(true)
    {
        int eventStart = StringFind(xmlResponse, "<event>", pos);
        if(eventStart == -1) break;

        int eventEnd = StringFind(xmlResponse, "</event>", eventStart);
        if(eventEnd == -1) break;

        string eventBlock = StringSubstr(xmlResponse, eventStart, eventEnd - eventStart);

        //--- Extract fields
        NewsEvent evt;
        evt.time = ExtractXMLDateTime(eventBlock);
        evt.currency = ExtractXMLTag(eventBlock, "currencycode");
        evt.title = ExtractXMLTag(eventBlock, "title");
        evt.importance = (int)StringToInteger(ExtractXMLTag(eventBlock, "impact"));

        if(evt.importance >= InpNews_MinImportance)
        {
            int size = ArraySize(g_NewsEvents);
            ArrayResize(g_NewsEvents, size + 1);
            g_NewsEvents[size] = evt;
        }

        pos = eventEnd;
    }

    g_NewsLastUpdate = TimeCurrent();

    if(InpVerboseLogs)
        Print("✅ NEWS CACHE: ", ArraySize(g_NewsEvents), " événements chargés (importance ≥", InpNews_MinImportance, ")");
}

//+------------------------------------------------------------------+
//| Helper: Extract XML tag value                                   |
//+------------------------------------------------------------------+
string ExtractXMLTag(string xml, string tag)
{
    string openTag = "<" + tag + ">";
    string closeTag = "</" + tag + ">";

    int start = StringFind(xml, openTag);
    if(start == -1) return "";

    start += StringLen(openTag);
    int end = StringFind(xml, closeTag, start);
    if(end == -1) return "";

    return StringSubstr(xml, start, end - start);
}

//+------------------------------------------------------------------+
//| Helper: Extract datetime from XML                               |
//+------------------------------------------------------------------+
datetime ExtractXMLDateTime(string xml)
{
    string dateStr = ExtractXMLTag(xml, "date");
    if(dateStr == "") return 0;

    // Format: "2025-01-15 14:30:00"
    return StringToTime(dateStr);
}

//+------------------------------------------------------------------+
//| AMÉLIORATION #10: Check News Filter                             |
//+------------------------------------------------------------------+
bool CheckNewsFilter()
{
    if(!InpNews_Enabled) return true;

    //--- Update cache if needed
    UpdateNewsCache();

    //--- Check cached news events
    datetime now = TimeCurrent();

    for(int i = 0; i < ArraySize(g_NewsEvents); i++)
    {
        datetime pauseBefore = g_NewsEvents[i].time - InpNews_PauseBeforeMinutes * 60;
        datetime pauseAfter = g_NewsEvents[i].time + InpNews_PauseAfterMinutes * 60;

        if(now >= pauseBefore && now <= pauseAfter)
        {
            if(InpVerboseLogs)
            {
                Print("Filtre NEWS: ", g_NewsEvents[i].currency, " - ", g_NewsEvents[i].title,
                      " (Importance:", g_NewsEvents[i].importance, ") à ",
                      TimeToString(g_NewsEvents[i].time, TIME_DATE|TIME_MINUTES));
            }
            return false;
        }
    }

    return true;
}
//+------------------------------------------------------------------+
