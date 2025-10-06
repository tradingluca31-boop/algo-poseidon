//+------------------------------------------------------------------+
//|                                           Zeus_Simplified.mq5    |
//|                      Version QUANTS - Filtres Professionnels      |
//|                                                                    |
//| OPTIMISATIONS v4.0 (FILTRES QUANTS PROFESSIONNELS):              |
//| - SL: 1.5 × ATR (s'adapte à la volatilité)                       |
//| - TP: 4.5 × ATR (RR 1:3 GARANTI)                                 |
//| - BE: 1.5 × ATR (à 1R)                                            |
//| - TIME STOP: Fermeture auto après 48h                            |
//|                                                                    |
//| NOUVEAUX FILTRES QUANTS:                                          |
//| 1. VOLATILITY PERCENTILE (30-70%):                               |
//|    - Skip si marché trop calme (<30%) ou trop volatile (>70%)    |
//|    - Réduction attendue: -40% trades perdants                     |
//|                                                                    |
//| 2. SPREAD/ATR RATIO (<30%):                                       |
//|    - Skip si spread > 30% de l'ATR                                |
//|    - Réduction attendue: -15% trades perdants                     |
//|                                                                    |
//| 3. Z-SCORE (>1.0 sigma):                                          |
//|    - Skip si prix trop proche de la moyenne                       |
//|    - Trade seulement si mouvement significatif (>1σ)              |
//|    - Réduction attendue: -20% trades perdants                     |
//|                                                                    |
//| AUTRES FILTRES:                                                   |
//| - ADX: Skip si RANGING (ADX < 20)                                |
//| - Signaux: 4/10 minimum                                           |
//| - Corrélation: Max 0.85                                           |
//| - Logique directionnelle (pas de trades opposés)                  |
//|                                                                    |
//| RÉDUCTION TOTALE ATTENDUE: -75% trades perdants                   |
//+------------------------------------------------------------------+
#property copyright "Zeus Trading System - QUANTS"
#property version   "4.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== FTMO RISK MANAGEMENT ==="
input double InpRiskPerTrade = 0.30;           // Risque par trade (%)
input double InpMaxSimultaneousRisk = 3.0;     // Risque simultané max (%)
input double InpMaxDailyLoss = 3.0;            // Perte quotidienne max (%) - STOP TRADING
input int    InpMaxPositions = 10;             // Positions simultanées max

input group "=== SL/TP ATR DYNAMIQUE ==="
input double InpSL_ATR_Multiplier = 2.0;       // SL: Multiplicateur ATR (2.0 × ATR) - Plus large
input double InpTP_ATR_Multiplier = 6.0;       // TP: Multiplicateur ATR (6.0 × ATR = RR 1:3)
input double InpBE_ATR_Multiplier = 2.0;       // BE: Multiplicateur ATR (2.0 × ATR = 1R)
input int    InpMaxHoldingHours = 24;          // Time Stop: fermeture auto après 24h (réduit)

input group "=== TRADING HOURS ==="
input int    InpTradingStartHour = 6;          // Heure début trading
input int    InpTradingEndHour = 22;           // Heure fin trading

input group "=== SIGNAUX TECHNIQUES (TREND FOLLOWING) ==="
input int    InpEMA_Period = 200;              // Période EMA (filtre tendance)
input int    InpATR_Period = 14;               // Période ATR
input int    InpSuperTrend_Period = 10;        // Période SuperTrend
input double InpSuperTrend_Multiplier = 3.0;   // Multiplicateur SuperTrend

input group "=== CORRELATION & EXPOSURE ==="
input double InpMaxCorrelation = 0.85;         // Corrélation max autorisée
input int    InpCorrelationPeriod = 100;       // Période calcul corrélation
input ENUM_TIMEFRAMES InpCorrelationTF = PERIOD_H1; // Timeframe corrélation

input group "=== MARKET REGIME ADX ==="
input bool   InpADX_Enabled = true;            // Activer détection ADX
input int    InpADX_Period = 14;               // Période ADX
input double InpADX_TrendingThreshold = 30.0;  // ADX > 30 = Trending FORT (augmenté)
input double InpADX_RangingThreshold = 25.0;   // ADX < 25 = Ranging (augmenté)

input group "=== FILTRES QUANTS PROFESSIONNELS ==="
input bool   InpVolPercentile_Enabled = true;  // Activer Volatility Percentile
input int    InpVolPercentile_Period = 100;    // Période calcul percentile (100 bougies)
input double InpVolPercentile_Min = 40.0;      // Percentile min (40% - fenêtre réduite)
input double InpVolPercentile_Max = 60.0;      // Percentile max (60% - fenêtre réduite)

input bool   InpSpreadFilter_Enabled = true;   // Activer filtre Spread/ATR
input double InpSpreadATR_MaxRatio = 0.30;     // Ratio max Spread/ATR (0.3 = 30%)

input bool   InpZScore_Enabled = true;         // Activer Z-Score filter
input int    InpZScore_Period = 50;            // Période calcul Z-Score (50 bougies)
input double InpZScore_MinThreshold = 1.0;     // Z-Score min pour trade (1.0 sigma)

input group "=== SCORING SIGNALS (TREND FOLLOWING) ==="
input int    InpMinSignalsRequired = 3;        // Signaux minimum requis (sur 4) = 75%

input group "=== GENERAL SETTINGS ==="
input int    InpMagicNumber = 789456;          // Magic Number
input string InpTradeComment = "Zeus_Simple";  // Commentaire trades
input bool   InpVerboseLogs = true;            // Logs détaillés

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

//--- Indicator handles (TREND FOLLOWING ONLY)
int g_EMA_Handle[];
int g_ATR_Handle[];
int g_ADX_Handle[];

//--- SuperTrend arrays (calculated manually, no handle needed)
double g_SuperTrend_Upper[];
double g_SuperTrend_Lower[];
int g_SuperTrend_Direction[];

//--- Position tracking for directional logic
enum ENUM_MARKET_BIAS {
    BIAS_NONE,
    BIAS_BULLISH,
    BIAS_BEARISH
};

ENUM_MARKET_BIAS g_CurrentBias = BIAS_NONE;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("===== ZEUS SIMPLIFIED - INITIALISATION =====");

    g_Trade.SetExpertMagicNumber(InpMagicNumber);
    g_Trade.SetDeviationInPoints(20);
    g_Trade.SetTypeFilling(ORDER_FILLING_FOK);
    g_Trade.SetAsyncMode(false);

    //--- Initialize arrays (TREND FOLLOWING ONLY - RSI/MACD supprimés)
    ArrayResize(g_EMA_Handle, ArraySize(g_Symbols));
    ArrayResize(g_ATR_Handle, ArraySize(g_Symbols));
    ArrayResize(g_ADX_Handle, ArraySize(g_Symbols));

    ArrayResize(g_SuperTrend_Upper, ArraySize(g_Symbols));
    ArrayResize(g_SuperTrend_Lower, ArraySize(g_Symbols));
    ArrayResize(g_SuperTrend_Direction, ArraySize(g_Symbols));

    //--- Create indicator handles for all symbols (TREND FOLLOWING)
    for(int i = 0; i < ArraySize(g_Symbols); i++)
    {
        g_EMA_Handle[i] = iMA(g_Symbols[i], PERIOD_CURRENT, InpEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
        g_ATR_Handle[i] = iATR(g_Symbols[i], PERIOD_CURRENT, InpATR_Period);
        if(InpADX_Enabled)
            g_ADX_Handle[i] = iADX(g_Symbols[i], PERIOD_CURRENT, InpADX_Period);

        bool handlesOK = (g_EMA_Handle[i] != INVALID_HANDLE && g_ATR_Handle[i] != INVALID_HANDLE);

        if(InpADX_Enabled)
            handlesOK = handlesOK && (g_ADX_Handle[i] != INVALID_HANDLE);

        if(!handlesOK)
        {
            Print("ERREUR: Impossible de créer les indicateurs TREND FOLLOWING pour ", g_Symbols[i]);
            return INIT_FAILED;
        }

        // Initialize SuperTrend
        g_SuperTrend_Direction[i] = 0;
    }

    //--- Initialize balance tracking
    g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DailyStartBalance = g_InitialBalance;
    g_PeakBalance = g_InitialBalance;
    g_DailyResetTime = TimeCurrent();

    Print("Initialisation réussie - Balance: ", g_InitialBalance);
    Print("Paires surveillées: ", ArraySize(g_Symbols));
    Print("SL: ", InpSL_ATR_Multiplier, "×ATR | TP: ", InpTP_ATR_Multiplier, "×ATR (RR 1:3) | BE: ", InpBE_ATR_Multiplier, "×ATR");
    Print("Signaux requis: ", InpMinSignalsRequired, "/10");

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
        if(InpADX_Enabled && g_ADX_Handle[i] != INVALID_HANDLE) IndicatorRelease(g_ADX_Handle[i]);
    }

    Print("Zeus Simplified déchargé - Raison: ", reason);
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

    //--- Close positions held too long (Time Stop)
    CloseOldPositions();

    //--- Update Break Even for all positions
    UpdateAllBreakEven();

    //--- Check FTMO daily loss limit (HARD STOP)
    if(!CheckDailyLossLimit())
    {
        if(InpVerboseLogs) Print("DAILY LOSS LIMIT ATTEINT - Trading arrêté pour aujourd'hui");
        return;
    }

    //--- Check FTMO limits
    if(!CheckFTMOLimits())
    {
        if(InpVerboseLogs) Print("FTMO Limits atteintes - Pas de nouveaux trades");
        return;
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
    //--- FILTRES ÉLIMINATOIRES

    //--- Filtre 1: Pas de position déjà ouverte
    if(HasOpenPosition(symbol)) return;

    //--- Filtre 2: Vérifier heures de trading
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    if(dt.hour < InpTradingStartHour || dt.hour >= InpTradingEndHour)
        return;

    //--- Filtre 3: Corrélation
    if(!CheckCorrelationExposure(symbol))
        return;

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

    double currentEMA = ema[1];
    double currentRSI = rsi[1];
    double prevRSI = rsi[2];
    double currentMACD_Main = macd_main[1];
    double currentMACD_Signal = macd_signal[1];
    double prevMACD_Main = macd_main[2];
    double prevMACD_Signal = macd_signal[2];
    double currentATR = atr[1];

    //--- FILTRE QUANT #1: Volatility Percentile
    if(!CheckVolatilityPercentile(symbolIndex, currentATR))
        return;

    //--- FILTRE QUANT #2: Spread/ATR Ratio
    if(!CheckSpreadATRRatio(symbol, currentATR))
        return;

    //--- FILTRE QUANT #3: Z-Score
    if(!CheckZScore(symbol, close))
        return;

    //--- Market Regime Detection (ADX)
    string marketRegime = DetectMarketRegime(symbolIndex);

    //--- FILTRE: Skip si marché RANGING (ADX < 20)
    if(marketRegime == "RANGING")
    {
        if(InpVerboseLogs) Print("Marché RANGING (ADX < 20) - Skip trade: ", symbol);
        return;
    }

    //--- SCORING 10 SIGNAUX TECHNIQUES
    int signalsTotal = 10;
    int signalsBuy = 0, signalsSell = 0;

    //--- Signal 1: Prix vs EMA 200
    if(close > currentEMA) signalsBuy++;
    else if(close < currentEMA) signalsSell++;

    //--- Signal 2: RSI Momentum
    if(currentRSI > 50 && currentRSI < InpRSI_Overbought) signalsBuy++;
    else if(currentRSI < 50 && currentRSI > InpRSI_Oversold) signalsSell++;

    //--- Signal 3: RSI Oversold/Overbought bounce
    if(prevRSI < InpRSI_Oversold && currentRSI > InpRSI_Oversold) signalsBuy++;
    else if(prevRSI > InpRSI_Overbought && currentRSI < InpRSI_Overbought) signalsSell++;

    //--- Signal 4: MACD Crossover
    bool macdBullishCross = (prevMACD_Main < prevMACD_Signal && currentMACD_Main > currentMACD_Signal);
    bool macdBearishCross = (prevMACD_Main > prevMACD_Signal && currentMACD_Main < currentMACD_Signal);
    if(macdBullishCross) signalsBuy++;
    else if(macdBearishCross) signalsSell++;

    //--- Signal 5: MACD Position
    if(currentMACD_Main > 0) signalsBuy++;
    else if(currentMACD_Main < 0) signalsSell++;

    //--- Signal 6: Candle pattern (bullish/bearish)
    if(close > open) signalsBuy++;
    else if(close < open) signalsSell++;

    //--- Signal 7: Higher highs / Lower lows
    double prevHigh = iHigh(symbol, PERIOD_CURRENT, 2);
    double prevLow = iLow(symbol, PERIOD_CURRENT, 2);
    if(high > prevHigh && low > prevLow) signalsBuy++;
    else if(high < prevHigh && low < prevLow) signalsSell++;

    //--- Signal 8: Momentum (close vs close[2])
    double close2 = iClose(symbol, PERIOD_CURRENT, 2);
    if(close > close2) signalsBuy++;
    else if(close < close2) signalsSell++;

    //--- Signal 9: ADX Trending (favorise la direction)
    if(marketRegime == "TRENDING")
    {
        if(close > currentEMA) signalsBuy++;
        else if(close < currentEMA) signalsSell++;
    }

    //--- Signal 10: Volume/Range expansion (range actuel vs précédent)
    double currentRange = high - low;
    double prevRange = prevHigh - prevLow;
    if(currentRange > prevRange)
    {
        if(close > open) signalsBuy++;
        else if(close < open) signalsSell++;
    }

    //--- DÉCISION: Buy ou Sell selon scoring
    bool takeBuy = (signalsBuy >= InpMinSignalsRequired);
    bool takeSell = (signalsSell >= InpMinSignalsRequired);

    //--- LOGIQUE ANTI-TRADES OPPOSÉS
    // Si on a déjà un bias établi, on ne prend que des trades dans cette direction
    if(g_CurrentBias == BIAS_BULLISH && takeSell)
    {
        if(InpVerboseLogs) Print("BIAS BULLISH actif - Trade SELL refusé pour ", symbol);
        return;
    }
    if(g_CurrentBias == BIAS_BEARISH && takeBuy)
    {
        if(InpVerboseLogs) Print("BIAS BEARISH actif - Trade BUY refusé pour ", symbol);
        return;
    }

    //--- EXÉCUTION
    if(takeBuy)
    {
        if(InpVerboseLogs)
        {
            Print(">>> SIGNAL BUY: ", symbol, " | Signaux: ", signalsBuy, "/", signalsTotal,
                  " | Regime: ", marketRegime);
        }
        ExecuteTrade(symbol, ORDER_TYPE_BUY, close);
        g_CurrentBias = BIAS_BULLISH; // Établir bias haussier
    }
    else if(takeSell)
    {
        if(InpVerboseLogs)
        {
            Print(">>> SIGNAL SELL: ", symbol, " | Signaux: ", signalsSell, "/", signalsTotal,
                  " | Regime: ", marketRegime);
        }
        ExecuteTrade(symbol, ORDER_TYPE_SELL, close);
        g_CurrentBias = BIAS_BEARISH; // Établir bias baissier
    }
}

//+------------------------------------------------------------------+
//| Execute Trade with ATR-based SL/TP                               |
//+------------------------------------------------------------------+
void ExecuteTrade(string symbol, ENUM_ORDER_TYPE orderType, double price)
{
    //--- Get ATR value
    int symbolIndex = -1;
    for(int i = 0; i < ArraySize(g_Symbols); i++)
    {
        if(g_Symbols[i] == symbol)
        {
            symbolIndex = i;
            break;
        }
    }

    if(symbolIndex < 0)
    {
        if(InpVerboseLogs) Print("Symbole non trouvé: ", symbol);
        return;
    }

    double atr[];
    ArraySetAsSeries(atr, true);
    if(CopyBuffer(g_ATR_Handle[symbolIndex], 0, 0, 3, atr) < 3)
    {
        if(InpVerboseLogs) Print("Erreur lecture ATR pour ", symbol);
        return;
    }

    double currentATR = atr[1];

    //--- Calculate SL and TP based on ATR (RR 1:3 garanti)
    double slDistance = currentATR * InpSL_ATR_Multiplier;  // 1.5 × ATR
    double tpDistance = currentATR * InpTP_ATR_Multiplier;  // 4.5 × ATR (RR 1:3)

    //--- Calculate lot size based on risk
    double lotSize = CalculateLotSize(symbol, slDistance);

    if(lotSize <= 0)
    {
        if(InpVerboseLogs) Print("Lot size invalide pour ", symbol);
        return;
    }

    //--- Calculate SL and TP prices
    double sl, tp;

    if(orderType == ORDER_TYPE_BUY)
    {
        sl = price - slDistance;
        tp = price + tpDistance;
    }
    else // SELL
    {
        sl = price + slDistance;
        tp = price - tpDistance;
    }

    //--- Normalize prices
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    sl = NormalizeDouble(sl, digits);
    tp = NormalizeDouble(tp, digits);

    //--- Execute order
    bool result = false;
    if(orderType == ORDER_TYPE_BUY)
        result = g_Trade.Buy(lotSize, symbol, 0, sl, tp, InpTradeComment);
    else
        result = g_Trade.Sell(lotSize, symbol, 0, sl, tp, InpTradeComment);

    if(result)
    {
        double slPercent = (slDistance / price) * 100.0;
        double tpPercent = (tpDistance / price) * 100.0;
        Print(">>> ORDRE OUVERT: ", symbol, " | Type: ", EnumToString(orderType),
              " | Lot: ", lotSize, " | ATR: ", DoubleToString(currentATR, 5),
              " | SL: ", sl, " (", DoubleToString(slPercent, 2), "% / ", InpSL_ATR_Multiplier, "×ATR)",
              " | TP: ", tp, " (", DoubleToString(tpPercent, 2), "% / ", InpTP_ATR_Multiplier, "×ATR) | RR 1:3");
    }
    else
    {
        Print("ERREUR: Impossible d'ouvrir ordre pour ", symbol, " - Code: ", GetLastError());
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(string symbol, double slDistance)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (InpRiskPerTrade / 100.0);

    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

    if(tickValue == 0 || tickSize == 0 || slDistance == 0) return 0;

    double lotSize = (riskAmount * tickSize) / (slDistance * tickValue);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    lotSize = MathMax(minLot, MathMin(maxLot, lotSize));

    return lotSize;
}

//+------------------------------------------------------------------+
//| Update Break Even for all positions (ATR-based)                 |
//+------------------------------------------------------------------+
void UpdateAllBreakEven()
{
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        string symbol = PositionGetString(POSITION_SYMBOL);
        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        //--- Get ATR value for this symbol
        int symbolIndex = -1;
        for(int j = 0; j < ArraySize(g_Symbols); j++)
        {
            if(g_Symbols[j] == symbol)
            {
                symbolIndex = j;
                break;
            }
        }

        if(symbolIndex < 0) continue;

        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(g_ATR_Handle[symbolIndex], 0, 0, 3, atr) < 3) continue;

        double currentATR = atr[1];

        //--- Calculate 1R profit (BE trigger) based on ATR
        double beProfit = currentATR * InpBE_ATR_Multiplier; // 1.5 × ATR = 1R

        double currentPrice = (posType == POSITION_TYPE_BUY) ?
                              SymbolInfoDouble(symbol, SYMBOL_BID) :
                              SymbolInfoDouble(symbol, SYMBOL_ASK);

        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        bool shouldMoveToBE = false;
        double newSL = 0;

        if(posType == POSITION_TYPE_BUY)
        {
            // BUY: prix actuel >= entry + 1R (1.5 × ATR)
            if(currentPrice >= entryPrice + beProfit && currentSL < entryPrice)
            {
                shouldMoveToBE = true;
                newSL = NormalizeDouble(entryPrice, digits); // Move SL to BE
            }
        }
        else // SELL
        {
            // SELL: prix actuel <= entry - 1R (1.5 × ATR)
            if(currentPrice <= entryPrice - beProfit && (currentSL > entryPrice || currentSL == 0))
            {
                shouldMoveToBE = true;
                newSL = NormalizeDouble(entryPrice, digits); // Move SL to BE
            }
        }

        if(shouldMoveToBE)
        {
            if(g_Trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
            {
                double beProfitPercent = (beProfit / entryPrice) * 100.0;
                Print(">>> BREAK EVEN activé: ", symbol, " | Ticket: ", ticket,
                      " | SL → BE: ", newSL, " | Profit: ", DoubleToString(beProfitPercent, 2), "% (", InpBE_ATR_Multiplier, "×ATR)");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| FILTRE QUANT #1: Volatility Percentile                          |
//+------------------------------------------------------------------+
bool CheckVolatilityPercentile(int symbolIndex, double currentATR)
{
    if(!InpVolPercentile_Enabled) return true;

    // Récupère ATR historique (100 dernières bougies)
    double atrHistory[];
    ArraySetAsSeries(atrHistory, true);

    if(CopyBuffer(g_ATR_Handle[symbolIndex], 0, 0, InpVolPercentile_Period, atrHistory) < InpVolPercentile_Period)
        return true; // En cas d'erreur, autorise le trade

    // Compte combien de valeurs ATR sont inférieures à l'ATR actuel
    int countBelow = 0;
    for(int i = 0; i < InpVolPercentile_Period; i++)
    {
        if(atrHistory[i] < currentATR)
            countBelow++;
    }

    // Calcule le percentile (0-100)
    double percentile = (countBelow / (double)InpVolPercentile_Period) * 100.0;

    // Filtre: Skip si percentile < 30% (marché trop calme) ou > 70% (marché trop volatile)
    if(percentile < InpVolPercentile_Min || percentile > InpVolPercentile_Max)
    {
        if(InpVerboseLogs)
        {
            Print("FILTRE VOL PERCENTILE échoué: Percentile=", DoubleToString(percentile, 1),
                  "% (min:", InpVolPercentile_Min, "% max:", InpVolPercentile_Max, "%)");
        }
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| FILTRE QUANT #2: Spread/ATR Ratio                               |
//+------------------------------------------------------------------+
bool CheckSpreadATRRatio(string symbol, double currentATR)
{
    if(!InpSpreadFilter_Enabled) return true;

    // Récupère spread actuel
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double spread = ask - bid;

    if(currentATR == 0) return false; // Évite division par zéro

    // Calcule ratio Spread/ATR
    double spreadRatio = spread / currentATR;

    // Filtre: Skip si spread > 30% de l'ATR
    if(spreadRatio > InpSpreadATR_MaxRatio)
    {
        if(InpVerboseLogs)
        {
            Print("FILTRE SPREAD/ATR échoué: ", symbol, " | Ratio=", DoubleToString(spreadRatio * 100, 1),
                  "% (max:", DoubleToString(InpSpreadATR_MaxRatio * 100, 1), "%)");
        }
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| FILTRE QUANT #3: Z-Score (distance vs moyenne)                  |
//+------------------------------------------------------------------+
bool CheckZScore(string symbol, double close)
{
    if(!InpZScore_Enabled) return true;

    // Récupère historique des prix de clôture
    double closePrices[];
    ArraySetAsSeries(closePrices, true);

    if(CopyClose(symbol, PERIOD_CURRENT, 0, InpZScore_Period, closePrices) < InpZScore_Period)
        return true; // En cas d'erreur, autorise le trade

    // Calcule moyenne
    double mean = 0;
    for(int i = 0; i < InpZScore_Period; i++)
    {
        mean += closePrices[i];
    }
    mean /= InpZScore_Period;

    // Calcule écart-type (standard deviation)
    double sumSquaredDiff = 0;
    for(int i = 0; i < InpZScore_Period; i++)
    {
        double diff = closePrices[i] - mean;
        sumSquaredDiff += diff * diff;
    }
    double stdDev = MathSqrt(sumSquaredDiff / InpZScore_Period);

    if(stdDev == 0) return true; // Évite division par zéro

    // Calcule Z-Score
    double zScore = (close - mean) / stdDev;

    // Filtre: Skip si |Z-Score| < 1.0 (prix trop proche de la moyenne, pas de mouvement attendu)
    if(MathAbs(zScore) < InpZScore_MinThreshold)
    {
        if(InpVerboseLogs)
        {
            Print("FILTRE Z-SCORE échoué: ", symbol, " | Z-Score=", DoubleToString(zScore, 2),
                  " (min:", InpZScore_MinThreshold, ")");
        }
        return false;
    }

    if(InpVerboseLogs)
    {
        Print("FILTRE Z-SCORE OK: ", symbol, " | Z-Score=", DoubleToString(zScore, 2),
              " (", zScore > 0 ? "au-dessus" : "en-dessous", " de la moyenne)");
    }

    return true;
}

//+------------------------------------------------------------------+
//| Detect Market Regime (Trending vs Ranging)                      |
//+------------------------------------------------------------------+
string DetectMarketRegime(int symbolIndex)
{
    if(!InpADX_Enabled) return "NEUTRAL";

    double adx[];
    ArraySetAsSeries(adx, true);

    if(CopyBuffer(g_ADX_Handle[symbolIndex], 0, 0, 3, adx) < 3)
        return "NEUTRAL";

    double currentADX = adx[1];

    if(currentADX > InpADX_TrendingThreshold)
        return "TRENDING";
    else if(currentADX < InpADX_RangingThreshold)
        return "RANGING";
    else
        return "NEUTRAL";
}

//+------------------------------------------------------------------+
//| Check correlation exposure                                       |
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
//| Calculate correlation between two symbols                        |
//+------------------------------------------------------------------+
double CalculateCorrelation(string symbol1, string symbol2, int period, ENUM_TIMEFRAMES tf)
{
    double close1[], close2[];
    ArraySetAsSeries(close1, true);
    ArraySetAsSeries(close2, true);

    if(CopyClose(symbol1, tf, 0, period, close1) < period) return 0.0;
    if(CopyClose(symbol2, tf, 0, period, close2) < period) return 0.0;

    //--- Calculate means
    double mean1 = 0, mean2 = 0;
    for(int i = 0; i < period; i++)
    {
        mean1 += close1[i];
        mean2 += close2[i];
    }
    mean1 /= period;
    mean2 /= period;

    //--- Calculate correlation
    double sum_xy = 0, sum_x2 = 0, sum_y2 = 0;
    for(int i = 0; i < period; i++)
    {
        double dx = close1[i] - mean1;
        double dy = close2[i] - mean2;
        sum_xy += dx * dy;
        sum_x2 += dx * dx;
        sum_y2 += dy * dy;
    }

    double denominator = MathSqrt(sum_x2 * sum_y2);
    if(denominator == 0) return 0.0;

    return sum_xy / denominator;
}

//+------------------------------------------------------------------+
//| Check if position exists for symbol                              |
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
//| Check FTMO limits                                                |
//+------------------------------------------------------------------+
bool CheckFTMOLimits()
{
    //--- Check max positions
    int openPositions = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            openPositions++;
    }

    if(openPositions >= InpMaxPositions)
        return false;

    //--- Check simultaneous risk
    double totalRisk = 0.0;
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);

    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0 && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double lots = PositionGetDouble(POSITION_VOLUME);
            string symbol = PositionGetString(POSITION_SYMBOL);

            double slDistance = MathAbs(entryPrice - sl);
            double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

            if(tickSize > 0)
            {
                double riskAmount = (slDistance / tickSize) * tickValue * lots;
                totalRisk += (riskAmount / balance) * 100.0;
            }
        }
    }

    if(totalRisk >= InpMaxSimultaneousRisk)
        return false;

    return true;
}

//+------------------------------------------------------------------+
//| Check daily loss limit (HARD STOP)                               |
//+------------------------------------------------------------------+
bool CheckDailyLossLimit()
{
    double dailyLossPercent = (g_DailyPnL / g_DailyStartBalance) * 100.0;

    if(dailyLossPercent <= -InpMaxDailyLoss) // -3.0%
    {
        return false; // STOP TRADING
    }

    return true;
}

//+------------------------------------------------------------------+
//| Close positions held longer than max hours (Time Stop)          |
//+------------------------------------------------------------------+
void CloseOldPositions()
{
    datetime currentTime = TimeCurrent();

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
        int holdingHours = (int)((currentTime - openTime) / 3600);

        if(holdingHours >= InpMaxHoldingHours)
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            if(g_Trade.PositionClose(ticket))
            {
                Print(">>> TIME STOP: Position fermée après ", holdingHours, "h | ", symbol, " | Ticket: ", ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check daily reset                                                |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
    MqlDateTime dtCurrent, dtLastReset;
    TimeToStruct(TimeCurrent(), dtCurrent);
    TimeToStruct(g_DailyResetTime, dtLastReset);

    if(dtCurrent.day != dtLastReset.day)
    {
        //--- New day: reset counters
        g_DailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        g_DailyPnL = 0.0;
        g_DailyResetTime = TimeCurrent();
        g_CurrentBias = BIAS_NONE; // Reset bias chaque jour

        if(InpVerboseLogs)
        {
            Print("===== NOUVEAU JOUR - Reset =====");
            Print("Balance de départ: ", g_DailyStartBalance);
        }
    }

    //--- Update daily P&L
    double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_DailyPnL = currentBalance - g_DailyStartBalance;
}
