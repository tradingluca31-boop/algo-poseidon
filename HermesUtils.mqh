//+------------------------------------------------------------------+
//|                                                  HermesUtils.mqh |
//|                                          Algo Hermes Trading Bot |
//|                      https://github.com/tradingluca31-boop/HERMES |
//+------------------------------------------------------------------+
#property copyright "tradingluca31-boop"
#property link      "https://github.com/tradingluca31-boop/HERMES"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Variables externes pour le logging                              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Fonction d'obtention de l'heure de Paris                        |
//+------------------------------------------------------------------+
datetime GetParisTime()
{
    return TimeCurrent();
}

//+------------------------------------------------------------------+
//| Fonction de calcul de la taille de lot                          |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    CAccountInfo account;
    double balance = account.Balance();
    double risk_amount = balance * risk_per_trade / 100.0;

    double price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double pip_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double stop_distance = price * stop_loss_pct / 100.0;

    double lot_size = risk_amount / (stop_distance / SymbolInfoDouble(Symbol(), SYMBOL_POINT) * pip_value);

    // Limites
    if(lot_size < min_lot_size) lot_size = min_lot_size;
    if(lot_size > max_lot_size) lot_size = max_lot_size;

    return NormalizeDouble(lot_size, 2);
}

//+------------------------------------------------------------------+
//| Initialisation du logging                                       |
//+------------------------------------------------------------------+
void InitializeLogging()
{
    string filename = "HERMES_" + TimeToString(TimeCurrent(), TIME_DATE) + ".log";
    log_handle = FileOpen(filename, FILE_WRITE | FILE_TXT | FILE_ANSI);
}

//+------------------------------------------------------------------+
//| Fonction de logging                                             |
//+------------------------------------------------------------------+
void LogMessage(string type, string message)
{
    if(log_handle != INVALID_HANDLE)
    {
        string log_entry = StringFormat("[%s] %s: %s\n",
                                      TimeToString(GetParisTime(), TIME_DATE | TIME_MINUTES),
                                      type,
                                      message);
        FileWrite(log_handle, log_entry);
        FileFlush(log_handle);
    }
}

//+------------------------------------------------------------------+
//| Fonction de mise à jour des données d'indicateurs               |
//+------------------------------------------------------------------+
bool UpdateIndicatorData(int h1_ema21_h, int h1_ema55_h, int h1_smma50_h, int h1_smma200_h,
                         int h4_smma200_h, int h4_rsi_h,
                         double &ema21[], double &ema55[], double &smma50[], double &smma200[],
                         double &h4_smma200[], double &h4_rsi[])
{
    // Copie des données
    if(CopyBuffer(h1_ema21_h, 0, 0, 3, ema21) <= 0) return false;
    if(CopyBuffer(h1_ema55_h, 0, 0, 3, ema55) <= 0) return false;
    if(CopyBuffer(h1_smma50_h, 0, 0, 3, smma50) <= 0) return false;
    if(CopyBuffer(h1_smma200_h, 0, 0, 3, smma200) <= 0) return false;
    if(CopyBuffer(h4_smma200_h, 0, 0, 3, h4_smma200) <= 0) return false;
    if(CopyBuffer(h4_rsi_h, 0, 0, 3, h4_rsi) <= 0) return false;

    return true;
}

//+------------------------------------------------------------------+
//| Filtre horaire                                                  |
//+------------------------------------------------------------------+
bool CheckTimeFilter()
{
    MqlDateTime time_struct;
    TimeToStruct(GetParisTime(), time_struct);
    int current_hour = time_struct.hour;

    return (current_hour >= start_hour && current_hour <= end_hour);
}

//+------------------------------------------------------------------+
//| Signal Movement H1                                              |
//+------------------------------------------------------------------+
bool CheckMovementH1Signal(double &ema21[], double &ema55[])
{
    // Vérifie si les EMAs sont en mouvement ascendant ou descendant
    bool ema21_rising = ema21[0] > ema21[1];
    bool ema55_rising = ema55[0] > ema55[1];

    return (ema21_rising && ema55_rising) || (!ema21_rising && !ema55_rising);
}

//+------------------------------------------------------------------+
//| Signal Cross EMA21/55 H1                                        |
//+------------------------------------------------------------------+
int CheckEMACrossSignal(double &ema21[], double &ema55[])
{
    bool cross_up = (ema21[0] > ema55[0] && ema21[1] <= ema55[1]);
    bool cross_down = (ema21[0] < ema55[0] && ema21[1] >= ema55[1]);

    if(cross_up) return 1;   // Long
    if(cross_down) return -1; // Short
    return 0;                // Pas de signal
}

//+------------------------------------------------------------------+
//| Signal Cross SMMA50/200 H1                                      |
//+------------------------------------------------------------------+
int CheckSMMACrossSignal(double &smma50[], double &smma200[])
{
    bool cross_up = (smma50[0] > smma200[0] && smma50[1] <= smma200[1]);
    bool cross_down = (smma50[0] < smma200[0] && smma50[1] >= smma200[1]);

    if(cross_up) return 1;   // Long
    if(cross_down) return -1; // Short
    return 0;                // Pas de signal
}

//+------------------------------------------------------------------+
//| Signal Momentum M15                                             |
//+------------------------------------------------------------------+
int CheckMomentumM15Signal()
{
    double close_current = iClose(Symbol(), PERIOD_M15, 0);
    double close_previous = iClose(Symbol(), PERIOD_M15, 1);
    double close_2 = iClose(Symbol(), PERIOD_M15, 2);

    // Momentum basé sur 3 bougies consécutives
    if(close_current > close_previous && close_previous > close_2)
        return 1;  // Long
    if(close_current < close_previous && close_previous < close_2)
        return -1; // Short

    return 0; // Pas de signal
}

//+------------------------------------------------------------------+
//| Filtre Tendance H4                                              |
//+------------------------------------------------------------------+
bool CheckTrendH4Filter(int signal_direction, double &smma200_h4[])
{
    double current_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);

    if(signal_direction > 0) // Long
        return current_price > smma200_h4[0];
    else if(signal_direction < 0) // Short
        return current_price < smma200_h4[0];

    return true;
}

//+------------------------------------------------------------------+
//| Filtre RSI H4                                                   |
//+------------------------------------------------------------------+
bool CheckRSIH4Filter(int signal_direction, double &rsi_h4[])
{
    if(signal_direction > 0) // Long
        return rsi_h4[0] < rsi_overbought_h4;
    else if(signal_direction < 0) // Short
        return rsi_h4[0] > rsi_oversold_h4;

    return true;
}

//+------------------------------------------------------------------+
//| Filtre d'exposition                                             |
//+------------------------------------------------------------------+
string CheckExposureFilter()
{
    if(!block_same_pair_on_off && !block_other_crypto_on_off)
        return "";

    string current_symbol = Symbol();

    for(int i = 0; i < PositionsTotal(); i++)
    {
        CPositionInfo pos;
        if(!pos.SelectByIndex(i)) continue;
        if(pos.Magic() != HERMES_MAGIC) continue;

        string pos_symbol = pos.Symbol();

        // Même paire
        if(block_same_pair_on_off && pos_symbol == current_symbol)
            return "FILTER_SAME_PAIR";

        // Autres cryptos
        if(block_other_crypto_on_off && pos_symbol != current_symbol)
        {
            for(int j = 0; j < ArraySize(supported_symbols); j++)
            {
                if(StringFind(pos_symbol, supported_symbols[j]) >= 0)
                    return "FILTER_OTHER_CRYPTO";
            }
        }
    }

    return "";
}

//+------------------------------------------------------------------+
//| Statut d'exposition                                             |
//+------------------------------------------------------------------+
string GetExposureStatus()
{
    int positions_count = 0;
    string positions_list = "";

    for(int i = 0; i < PositionsTotal(); i++)
    {
        CPositionInfo pos;
        if(!pos.SelectByIndex(i)) continue;
        if(pos.Magic() != HERMES_MAGIC) continue;

        positions_count++;
        positions_list += pos.Symbol() + " ";
    }

    return StringFormat("Positions actives: %d [%s]", positions_count, positions_list);
}

//+------------------------------------------------------------------+
//| Filtre News (basique)                                           |
//+------------------------------------------------------------------+
string CheckNewsFilter()
{
    // Implémentation basique - peut être étendue
    MqlDateTime time_struct;
    TimeToStruct(GetParisTime(), time_struct);

    // Éviter les heures de news importantes (exemple: 14h30-15h30 Paris)
    if(time_struct.hour == 14 && time_struct.min >= 30)
        return "News économiques US";
    if(time_struct.hour == 15 && time_struct.min <= 30)
        return "News économiques US";

    return "";
}

//+------------------------------------------------------------------+
//| Gestion du Break-Even                                           |
//+------------------------------------------------------------------+
bool ShouldApplyBreakEven(bool be_already_applied)
{
    if(be_already_applied) return false;

    CPositionInfo pos;
    if(!pos.Select(Symbol())) return false;

    double open_price = pos.PriceOpen();
    double current_price = (pos.PositionType() == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(Symbol(), SYMBOL_BID) :
                          SymbolInfoDouble(Symbol(), SYMBOL_ASK);

    double profit_pct = 0;
    if(pos.PositionType() == POSITION_TYPE_BUY)
        profit_pct = (current_price - open_price) / open_price * 100.0;
    else
        profit_pct = (open_price - current_price) / open_price * 100.0;

    return profit_pct >= be_trigger_pct;
}

//+------------------------------------------------------------------+
//| Application du Break-Even                                       |
//+------------------------------------------------------------------+
bool ApplyBreakEven()
{
    CPositionInfo pos;
    CTrade trade;

    if(!pos.Select(Symbol())) return false;

    double open_price = pos.PriceOpen();

    if(trade.PositionModify(pos.Ticket(), open_price, pos.TakeProfit()))
    {
        string be_msg = StringFormat("Break-Even appliqué à %.5f", open_price);
        Print(be_msg);
        LogMessage("BREAK_EVEN", be_msg);
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Logging des blocages                                            |
//+------------------------------------------------------------------+
void LogBlockage(SignalResult &signals, FilterResult &filters)
{
    string blockage_msg = StringFormat(
        "=== SIGNAL BLOQUÉ ===\n" +
        "Signaux: %s (Force: %d)\n" +
        "Direction: %s\n" +
        "Bloqué par: %s\n" +
        "Contexte: %s\n" +
        "Heure: %s",
        signals.active_signals,
        signals.signal_strength,
        (signals.direction > 0) ? "LONG" : (signals.direction < 0) ? "SHORT" : "NEUTRE",
        filters.blocked_by,
        filters.context_data,
        TimeToString(GetParisTime(), TIME_DATE | TIME_MINUTES)
    );

    LogMessage("BLOCKED", blockage_msg);
}

//+------------------------------------------------------------------+
//| Texte de la raison d'arrêt                                     |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason)
{
    switch(reason)
    {
        case REASON_PROGRAM: return "Expert recompilé";
        case REASON_REMOVE: return "Expert retiré du graphique";
        case REASON_RECOMPILE: return "Expert recompilé";
        case REASON_CHARTCHANGE: return "Changement de graphique";
        case REASON_CHARTCLOSE: return "Graphique fermé";
        case REASON_PARAMETERS: return "Paramètres modifiés";
        case REASON_ACCOUNT: return "Compte changé";
        case REASON_TEMPLATE: return "Template appliqué";
        case REASON_INITFAILED: return "Échec d'initialisation";
        case REASON_CLOSE: return "Terminal fermé";
        default: return "Raison inconnue";
    }
}