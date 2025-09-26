//+------------------------------------------------------------------+
//|                                                       HERMES.mq5 |
//|                                          Algo Hermes Trading Bot |
//|                      https://github.com/tradingluca31-boop/HERMES |
//+------------------------------------------------------------------+
#property copyright "tradingluca31-boop"
#property link      "https://github.com/tradingluca31-boop/HERMES"
#property version   "1.00"
#property description "Algorithme HERMES - Momentum Following pour BTC/ETH/SOL"
#property description "Date de création: 22 septembre 2025"
#property description "Ratio R:R 1:5 | SL 0.70% | TP 3.50% | Break-Even +1R"

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Trade/AccountInfo.mqh>

#include "HermesConfig.mqh"
#include "HermesUtils.mqh"

//+------------------------------------------------------------------+
//| Variables globales                                               |
//+------------------------------------------------------------------+
CTrade trade;
CPositionInfo position;
CSymbolInfo symbol_info;
CAccountInfo account;

// Indicateurs
int h1_ema21_handle, h1_ema55_handle;
int h1_smma50_handle, h1_smma200_handle;
int h4_smma200_handle, h4_rsi_handle;

// Buffers des indicateurs
double h1_ema21[], h1_ema55[];
double h1_smma50[], h1_smma200[];
double h4_smma200[], h4_rsi[];

// Variables de gestion
bool be_applied = false;           // Break-even déjà appliqué
datetime last_signal_time = 0;    // Dernière évaluation de signal
string current_symbol = "";       // Symbole actuel

// Variables de logging
int log_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Validation du symbole
    current_symbol = Symbol();
    if(!IsValidSymbol(current_symbol))
    {
        Print("HERMES ERROR: Symbole non supporté: ", current_symbol);
        Print("HERMES: Symboles supportés: BTCUSD, ETHUSD, SOLUSD");
        return INIT_FAILED;
    }

    // Configuration du trading
    trade.SetExpertMagicNumber(HERMES_MAGIC);
    trade.SetDeviationInPoints(10);
    trade.SetTypeFilling(ORDER_FILLING_FOK);

    // Initialisation des indicateurs H1
    h1_ema21_handle = iMA(current_symbol, PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
    h1_ema55_handle = iMA(current_symbol, PERIOD_H1, 55, 0, MODE_EMA, PRICE_CLOSE);
    h1_smma50_handle = iMA(current_symbol, PERIOD_H1, 50, 0, MODE_SMMA, PRICE_CLOSE);
    h1_smma200_handle = iMA(current_symbol, PERIOD_H1, 200, 0, MODE_SMMA, PRICE_CLOSE);

    // Initialisation des indicateurs H4
    h4_smma200_handle = iMA(current_symbol, PERIOD_H4, 200, 0, MODE_SMMA, PRICE_CLOSE);
    h4_rsi_handle = iRSI(current_symbol, PERIOD_H4, 14, PRICE_CLOSE);

    // Vérification des handles
    if(h1_ema21_handle == INVALID_HANDLE || h1_ema55_handle == INVALID_HANDLE ||
       h1_smma50_handle == INVALID_HANDLE || h1_smma200_handle == INVALID_HANDLE ||
       h4_smma200_handle == INVALID_HANDLE || h4_rsi_handle == INVALID_HANDLE)
    {
        Print("HERMES ERROR: Échec initialisation des indicateurs");
        return INIT_FAILED;
    }

    // Configuration des buffers
    ArraySetAsSeries(h1_ema21, true);
    ArraySetAsSeries(h1_ema55, true);
    ArraySetAsSeries(h1_smma50, true);
    ArraySetAsSeries(h1_smma200, true);
    ArraySetAsSeries(h4_smma200, true);
    ArraySetAsSeries(h4_rsi, true);

    // Initialisation du logging
    InitializeLogging();

    // Message de démarrage
    string start_msg = StringFormat(
        "=== HERMES v1.0.0 DÉMARRÉ ===\n" +
        "Symbole: %s\n" +
        "Heure: %s (Europe/Paris)\n" +
        "Paramètres: SL=%.2f%% | TP=%.2f%% | BE=%.2f%%\n" +
        "Filtres: RSI H4 [%d-%d] | News=%s | Expo_Same=%s | Expo_Other=%s",
        current_symbol,
        TimeToString(GetParisTime(), TIME_DATE | TIME_MINUTES),
        stop_loss_pct,
        take_profit_pct,
        be_trigger_pct,
        rsi_oversold_h4,
        rsi_overbought_h4,
        news_filter_on_off ? "ON" : "OFF",
        block_same_pair_on_off ? "ON" : "OFF",
        block_other_crypto_on_off ? "ON" : "OFF"
    );

    Print(start_msg);
    LogMessage("STARTUP", start_msg);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Libération des handles
    IndicatorRelease(h1_ema21_handle);
    IndicatorRelease(h1_ema55_handle);
    IndicatorRelease(h1_smma50_handle);
    IndicatorRelease(h1_smma200_handle);
    IndicatorRelease(h4_smma200_handle);
    IndicatorRelease(h4_rsi_handle);

    // Message d'arrêt
    string stop_msg = StringFormat(
        "=== HERMES ARRÊTÉ ===\n" +
        "Raison: %s\n" +
        "Heure: %s (Europe/Paris)",
        GetDeinitReasonText(reason),
        TimeToString(GetParisTime(), TIME_DATE | TIME_MINUTES)
    );

    Print(stop_msg);
    LogMessage("SHUTDOWN", stop_msg);

    // Fermeture du fichier de log
    if(log_handle != INVALID_HANDLE)
        FileClose(log_handle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Vérification des nouvelles bougies
    static datetime last_m15_time = 0;
    static datetime last_h1_time = 0;

    datetime current_m15_time = iTime(current_symbol, PERIOD_M15, 0);
    datetime current_h1_time = iTime(current_symbol, PERIOD_H1, 0);

    bool new_m15_candle = (current_m15_time != last_m15_time);
    bool new_h1_candle = (current_h1_time != last_h1_time);

    // Gestion des positions existantes (à chaque tick)
    ManageExistingPositions();

    // Évaluation des signaux seulement sur nouvelle bougie
    if(new_m15_candle || new_h1_candle)
    {
        last_m15_time = current_m15_time;
        last_h1_time = current_h1_time;

        // Mise à jour des données des indicateurs
        if(!UpdateIndicatorData(h1_ema21_handle, h1_ema55_handle, h1_smma50_handle, h1_smma200_handle,
                               h4_smma200_handle, h4_rsi_handle,
                               h1_ema21, h1_ema55, h1_smma50, h1_smma200, h4_smma200, h4_rsi))
        {
            LogMessage("ERROR", "Échec mise à jour des indicateurs");
            return;
        }

        // Évaluation des signaux et filtres
        EvaluateSignalsAndFilters();
    }
}

//+------------------------------------------------------------------+
//| Fonction d'évaluation des signaux et filtres                    |
//+------------------------------------------------------------------+
void EvaluateSignalsAndFilters()
{
    // Vérification filtre horaire d'abord
    if(!CheckTimeFilter())
    {
        return; // Pas de log pour filtre horaire (trop verbeux)
    }

    // Évaluation des signaux
    SignalResult signals = EvaluateSignals();

    // Si aucun signal, pas d'action
    if(signals.signal_strength == 0)
    {
        return;
    }

    // Évaluation des filtres
    FilterResult filters = EvaluateFilters(signals.direction);

    // Si un filtre bloque, log et arrêt
    if(!filters.all_passed)
    {
        LogBlockage(signals, filters);
        return;
    }

    // Tous les filtres passés - Ouverture de position
    OpenPosition(signals);
}

//+------------------------------------------------------------------+
//| Fonction d'évaluation des signaux                               |
//+------------------------------------------------------------------+
SignalResult EvaluateSignals()
{
    SignalResult result;
    result.signal_strength = 0;
    result.direction = 0;
    result.active_signals = "";

    // 1. Signal Movement H1
    if(CheckMovementH1Signal(h1_ema21, h1_ema55))
    {
        result.signal_strength++;
        result.active_signals += "MOVEMENT_H1 ";
    }

    // 2. Signal Cross EMA21/55 H1
    int ema_cross = CheckEMACrossSignal(h1_ema21, h1_ema55);
    if(ema_cross != 0)
    {
        result.signal_strength++;
        result.direction += ema_cross;
        result.active_signals += (ema_cross > 0) ? "EMA_CROSS_LONG " : "EMA_CROSS_SHORT ";
    }

    // 3. Signal Cross SMMA50/200 H1
    int smma_cross = CheckSMMACrossSignal(h1_smma50, h1_smma200);
    if(smma_cross != 0)
    {
        result.signal_strength++;
        result.direction += smma_cross;
        result.active_signals += (smma_cross > 0) ? "SMMA_CROSS_LONG " : "SMMA_CROSS_SHORT ";
    }

    // 4. Signal Momentum M15
    int momentum = CheckMomentumM15Signal();
    if(momentum != 0)
    {
        result.signal_strength++;
        result.direction += momentum;
        result.active_signals += (momentum > 0) ? "MOMENTUM_M15_LONG " : "MOMENTUM_M15_SHORT ";
    }

    // Détermination direction finale
    if(result.direction > 0)
        result.direction = 1;  // Long
    else if(result.direction < 0)
        result.direction = -1; // Short
    else
        result.direction = 0;  // Neutre

    return result;
}

//+------------------------------------------------------------------+
//| Fonction d'évaluation des filtres                               |
//+------------------------------------------------------------------+
FilterResult EvaluateFilters(int signal_direction)
{
    FilterResult result;
    result.all_passed = true;
    result.blocked_by = "";
    result.context_data = "";

    // 1. Filtre Tendance H4
    if(!CheckTrendH4Filter(signal_direction, h4_smma200))
    {
        result.all_passed = false;
        result.blocked_by = "FILTER_TREND_H4";
        double current_price = SymbolInfoDouble(current_symbol, SYMBOL_BID);
        result.context_data = StringFormat("Prix=%.5f vs SMMA200_H4=%.5f",
                                         current_price, h4_smma200[0]);
        return result;
    }

    // 2. Filtre RSI H4
    if(!CheckRSIH4Filter(signal_direction, h4_rsi))
    {
        result.all_passed = false;
        result.blocked_by = "FILTER_RSI_H4";
        result.context_data = StringFormat("RSI_H4=%.1f | Seuils=[%d-%d]",
                                         h4_rsi[0], rsi_oversold_h4, rsi_overbought_h4);
        return result;
    }

    // 3. Filtre Exposition
    string expo_filter = CheckExposureFilter();
    if(expo_filter != "")
    {
        result.all_passed = false;
        result.blocked_by = expo_filter;
        result.context_data = GetExposureStatus();
        return result;
    }

    // 4. Filtre News (si activé)
    if(news_filter_on_off)
    {
        string news_filter = CheckNewsFilter();
        if(news_filter != "")
        {
            result.all_passed = false;
            result.blocked_by = "FILTER_NEWS";
            result.context_data = news_filter;
            return result;
        }
    }

    return result;
}

//+------------------------------------------------------------------+
//| Fonction de gestion des positions existantes                    |
//+------------------------------------------------------------------+
void ManageExistingPositions()
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(!position.SelectByIndex(i))
            continue;

        if(position.Magic() != HERMES_MAGIC)
            continue;

        if(position.Symbol() != current_symbol)
            continue;

        // Gestion du Break-Even
        if(!be_applied && ShouldApplyBreakEven(be_applied))
        {
            if(ApplyBreakEven())
            {
                be_applied = true;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Fonction d'ouverture de position                                |
//+------------------------------------------------------------------+
void OpenPosition(SignalResult signals)
{
    double current_price = (signals.direction > 0) ?
                          SymbolInfoDouble(current_symbol, SYMBOL_ASK) :
                          SymbolInfoDouble(current_symbol, SYMBOL_BID);

    // Calcul des niveaux SL et TP
    double sl_price, tp_price;
    if(signals.direction > 0) // Long
    {
        sl_price = current_price * (1 - stop_loss_pct / 100.0);
        tp_price = current_price * (1 + take_profit_pct / 100.0);
    }
    else // Short
    {
        sl_price = current_price * (1 + stop_loss_pct / 100.0);
        tp_price = current_price * (1 - take_profit_pct / 100.0);
    }

    // Calcul du lot
    double lot_size = CalculateLotSize();

    // Ouverture de la position
    bool success = false;
    if(signals.direction > 0)
    {
        success = trade.Buy(lot_size, current_symbol, current_price, sl_price, tp_price,
                           "HERMES Long - " + signals.active_signals);
    }
    else
    {
        success = trade.Sell(lot_size, current_symbol, current_price, sl_price, tp_price,
                            "HERMES Short - " + signals.active_signals);
    }

    // Logging
    if(success)
    {
        be_applied = false; // Reset du break-even

        string entry_log = StringFormat(
            "=== POSITION OUVERTE ===\n" +
            "Symbole: %s\n" +
            "Direction: %s\n" +
            "Prix d'entrée: %.5f\n" +
            "Stop Loss: %.5f (%.2f%%)\n" +
            "Take Profit: %.5f (%.2f%%)\n" +
            "Lot: %.2f\n" +
            "Signaux actifs: %s\n" +
            "Heure: %s (Europe/Paris)",
            current_symbol,
            (signals.direction > 0) ? "LONG" : "SHORT",
            current_price,
            sl_price, stop_loss_pct,
            tp_price, take_profit_pct,
            lot_size,
            signals.active_signals,
            TimeToString(GetParisTime(), TIME_DATE | TIME_MINUTES)
        );

        Print(entry_log);
        LogMessage("ENTRY", entry_log);
    }
    else
    {
        string error_msg = StringFormat("ERREUR ouverture position: %d - %s",
                                      trade.ResultRetcode(), trade.ResultRetcodeDescription());
        Print(error_msg);
        LogMessage("ERROR", error_msg);
    }
}