//+------------------------------------------------------------------+
//|                                                HermesConfig.mqh |
//|                                          Algo Hermes Trading Bot |
//|                      https://github.com/tradingluca31-boop/HERMES |
//+------------------------------------------------------------------+
#property copyright "tradingluca31-boop"
#property link      "https://github.com/tradingluca31-boop/HERMES"

//+------------------------------------------------------------------+
//| Paramètres de l'algorithme HERMES                               |
//+------------------------------------------------------------------+

// Magic Number
#define HERMES_MAGIC 123456789

// Paramètres de risque
input double stop_loss_pct = 0.70;        // Stop Loss en %
input double take_profit_pct = 3.50;      // Take Profit en %
input double be_trigger_pct = 0.70;       // Break-Even trigger en %

// Paramètres RSI H4
input int rsi_oversold_h4 = 30;           // RSI H4 sur-vendu
input int rsi_overbought_h4 = 70;         // RSI H4 sur-acheté

// Filtres
input bool news_filter_on_off = true;           // Filtre News ON/OFF
input bool block_same_pair_on_off = true;       // Bloquer même paire
input bool block_other_crypto_on_off = true;    // Bloquer autres cryptos

// Paramètres de lot
input double risk_per_trade = 1.0;        // Risque par trade en %
input double min_lot_size = 0.01;         // Lot minimum
input double max_lot_size = 10.0;         // Lot maximum

// Paramètres horaires
input int start_hour = 8;                 // Heure de début (Europe/Paris)
input int end_hour = 22;                  // Heure de fin (Europe/Paris)

//+------------------------------------------------------------------+
//| Structures pour les signaux et filtres                          |
//+------------------------------------------------------------------+
struct SignalResult
{
    int signal_strength;     // Force du signal (0-4)
    int direction;          // Direction: 1=Long, -1=Short, 0=Neutre
    string active_signals;  // Liste des signaux actifs
};

struct FilterResult
{
    bool all_passed;        // Tous les filtres passés
    string blocked_by;      // Filtre qui bloque
    string context_data;    // Données contextuelles
};

//+------------------------------------------------------------------+
//| Symboles supportés                                              |
//+------------------------------------------------------------------+
string supported_symbols[] = {"BTCUSD", "ETHUSD", "SOLUSD"};

//+------------------------------------------------------------------+
//| Fonction de validation des symboles                             |
//+------------------------------------------------------------------+
bool IsValidSymbol(string symbol)
{
    for(int i = 0; i < ArraySize(supported_symbols); i++)
    {
        if(StringFind(symbol, supported_symbols[i]) >= 0)
            return true;
    }
    return false;
}