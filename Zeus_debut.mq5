//+------------------------------------------------------------------+
//|                                                  Zeus_debut.mq5  |
//|                        Expert Advisor Multi-Currency FTMO        |
//|                        Correlation LOCAL + Risk Management       |
//|                        7 Paires USD + FTMO Compliant             |
//+------------------------------------------------------------------+
#property copyright "Zeus Trading System"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

CTrade Trade;

//+------------------------------------------------------------------+
//| INPUTS CONFIGURATION                                              |
//+------------------------------------------------------------------+
input long     InpMagic                  = 20251003;
input bool     InpAllowBuys              = true;
input bool     InpAllowSells             = true;

// === SELECTION PAIRES USD ===
input bool     InpTrade_EURUSD           = true;
input bool     InpTrade_GBPUSD           = true;
input bool     InpTrade_USDJPY           = true;
input bool     InpTrade_USDCHF           = true;
input bool     InpTrade_AUDUSD           = true;
input bool     InpTrade_NZDUSD           = true;
input bool     InpTrade_USDCAD           = true;

// === FTMO RISK MANAGEMENT ===
input double   InpRiskPercent            = 0.30;     // Risque par trade (%)
input double   InpMaxRiskSimultaneous    = 3.0;      // Risque total simultane max (%)
input double   InpMaxDailyLoss           = 3.0;      // Perte max journaliere (%)
input double   InpMaxDrawdown            = 8.0;      // Drawdown max (%)
input int      InpMaxSimultaneousTrades  = 10;       // Max positions simultanees

// === CORRELATION SETTINGS ===
input bool     InpUseCorrelation         = true;     // Activer filtre correlation
input double   InpCorrelationThreshold   = 0.80;     // Seuil correlation (>0.80 = tres correle)
input int      InpCorrelationPeriod      = 100;      // Periode calcul (barres)
input ENUM_TIMEFRAMES InpCorrelationTF   = PERIOD_H1;// Timeframe correlation

// === SIGNAUX TRADING ===
input bool     InpUseEMA_Cross           = true;     // EMA 21/55 croisement
input bool     InpUseMacd                = true;     // MACD histogram
input bool     InpUseSMMA_Cross          = true;     // SMMA 50/200 croisement H1
input int      InpMinSignalsRequired     = 2;        // Signaux minimum requis (1, 2 ou 3)

// === MACD CONFIG ===
input int      InpMacdFast               = 20;
input int      InpMacdSlow               = 35;
input int      InpMacdSignal             = 15;

// === RISK / GESTION ===
input double   InpSL_PercentOfPrice      = 0.35;     // SL = % du prix d entree
input double   InpTP_PercentOfPrice      = 1.75;     // TP = % du prix d entree
input double   InpBE_TriggerPercent      = 1.0;      // Passer BE quand +1%
input int      InpMaxTradesPerDay        = 4;

// === SESSION HOURS ===
input ENUM_TIMEFRAMES InpSignalTF        = PERIOD_H1;
input int      InpSessionStartHour       = 6;
input int      InpSessionEndHour         = 15;
input int      InpSlippagePoints         = 20;
input bool     InpVerboseLogs            = false;

// === SMMA 50 TREND FILTER ===
input bool     InpUseSMMA50Trend         = true;
input int      InpSMMA_Period            = 50;
input ENUM_TIMEFRAMES InpSMMA_TF         = PERIOD_H4;

// === RSI FILTER ===
input bool     InpUseRSI                 = true;
input ENUM_TIMEFRAMES InpRSI_TF          = PERIOD_H4;
input int      InpRSI_Period             = 14;
input int      InpRSI_Overbought         = 70;
input int      InpRSI_Oversold           = 25;

//+------------------------------------------------------------------+
//| VARIABLES GLOBALES                                                |
//+------------------------------------------------------------------+
datetime lastBarTime = 0;
datetime g_LastResetDate = 0;
double   g_DailyPnL = 0.0;
double   g_InitialBalance = 0.0;
int      g_TradesToday = 0;

// Handles indicateurs
int hEMA21 = -1, hEMA55 = -1;
int hSMAfast = -1, hSMAslow = -1;
int hSMMA50 = -1;
int hSMMA50_Signal = -1, hSMMA200_Signal = -1;
int rsi_handle = INVALID_HANDLE;

// Cache correlation
struct CorrelationData {
    string pair1;
    string pair2;
    double correlation;
    datetime lastUpdate;
};
CorrelationData g_CorrelationCache[];
int g_CorrelationCacheSize = 0;
const int CORRELATION_CACHE_DURATION = 3600;

// Structure paires
struct PairInfo {
    string symbol;
    bool enabled;
};
PairInfo allPairs[7];

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    Trade.SetExpertMagicNumber(InpMagic);
    Trade.SetDeviationInPoints(InpSlippagePoints);

    // Initialiser balance FTMO
    g_InitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    g_LastResetDate = TimeCurrent() - (TimeCurrent() % 86400);

    // Initialiser paires
    allPairs[0].symbol = "EURUSD"; allPairs[0].enabled = InpTrade_EURUSD;
    allPairs[1].symbol = "GBPUSD"; allPairs[1].enabled = InpTrade_GBPUSD;
    allPairs[2].symbol = "USDJPY"; allPairs[2].enabled = InpTrade_USDJPY;
    allPairs[3].symbol = "USDCHF"; allPairs[3].enabled = InpTrade_USDCHF;
    allPairs[4].symbol = "AUDUSD"; allPairs[4].enabled = InpTrade_AUDUSD;
    allPairs[5].symbol = "NZDUSD"; allPairs[5].enabled = InpTrade_NZDUSD;
    allPairs[6].symbol = "USDCAD"; allPairs[6].enabled = InpTrade_USDCAD;

    // Creer indicateurs pour symbole actuel
    string sym = _Symbol;
    hEMA21 = iMA(sym, InpSignalTF, 21, 0, MODE_EMA, PRICE_CLOSE);
    hEMA55 = iMA(sym, InpSignalTF, 55, 0, MODE_EMA, PRICE_CLOSE);
    hSMAfast = iMA(sym, InpSignalTF, InpMacdFast, 0, MODE_SMA, PRICE_CLOSE);
    hSMAslow = iMA(sym, InpSignalTF, InpMacdSlow, 0, MODE_SMA, PRICE_CLOSE);
    hSMMA50 = iMA(sym, InpSMMA_TF, InpSMMA_Period, 0, MODE_SMMA, PRICE_CLOSE);
    hSMMA50_Signal = iMA(sym, PERIOD_H1, 50, 0, MODE_SMMA, PRICE_CLOSE);
    hSMMA200_Signal = iMA(sym, PERIOD_H1, 200, 0, MODE_SMMA, PRICE_CLOSE);
    rsi_handle = iRSI(sym, InpRSI_TF, InpRSI_Period, PRICE_CLOSE);

    Print("ZEUS DEBUT: Init OK - FTMO + Correlation LOCAL actives");

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // VERIFICATIONS FTMO
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(g_InitialBalance == 0) g_InitialBalance = balance;
    double totalDD = ((g_InitialBalance - equity) / g_InitialBalance) * 100.0;
    if(totalDD >= InpMaxDrawdown) { Print("FTMO STOP: DD ", totalDD, "%"); return; }

    // Daily loss
    datetime currentDate = TimeCurrent() - (TimeCurrent() % 86400);
    if(currentDate != g_LastResetDate) { g_DailyPnL = 0.0; g_TradesToday = 0; g_LastResetDate = currentDate; }

    HistorySelect(currentDate, TimeCurrent());
    g_DailyPnL = 0.0;
    for(int i = 0; i < HistoryDealsTotal(); i++) {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == InpMagic)
            g_DailyPnL += HistoryDealGetDouble(ticket, DEAL_PROFIT);
    }
    double dailyLossPercent = (g_DailyPnL / balance) * 100.0;
    if(dailyLossPercent <= -InpMaxDailyLoss) { Print("FTMO STOP: Daily Loss ", dailyLossPercent, "%"); return; }

    // Max positions
    int openPositions = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(PositionSelectByTicket(PositionGetTicket(i)) && PositionGetInteger(POSITION_MAGIC) == InpMagic)
            openPositions++;
    }
    if(openPositions >= InpMaxSimultaneousTrades) return;

    Print("Zeus_debut loaded successfully - Ready to trade");
}
