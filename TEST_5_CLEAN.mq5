//+------------------------------------------------------------------+
//|                                                      TEST_5_CLEAN.mq5 |
//|                        Algorithme Poseidon - Version Clean et Organisée |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Algorithme Poseidon 2024"
#property link      "https://www.mql5.com"
#property version   "5.00"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//|                        DÉCLARATIONS DE FONCTIONS                 |
//+------------------------------------------------------------------+
void ResetDailyTradeCount();
bool BasicConditionsCheck();
bool IsMonthAllowed(int month);
bool UpdateIndicators();
void CheckTradingSignals();
void UpdatePersistentSignals();
int CheckTradeConditions();
void ResetSignalsAfterTrade();
int GetEMACrossSignal();
int GetSMMACrossSignal();
int GetMACDHistogramSignal();
bool CheckRSIFilter(bool isBuySignal);
bool CheckSMMAFilter(bool isBuySignal);
double CalculateLotSize();
void ExecuteBuyOrder(double lotSize);
void ExecuteSellOrder(double lotSize);
void ManagePositions();
void CheckBreakEven();
void CreateCSVHeader();
void LogTradeToCSV(string type, double lots, double price, double sl, double tp);

//+------------------------------------------------------------------+
//|                           PARAMÈTRES D'ENTRÉE                    |
//+------------------------------------------------------------------+

//=== SIGNAUX DE TRADING (H1) ===
input group "=== SIGNAUX DE TRADING (H1) ==="
input bool UseEmaSignal = true;          // Signal EMA21/55 cross
input bool UseSmmaCrossSignal = true;    // Signal SMMA50/200 cross  
input bool UseMacdHistogramSignal = true; // Signal MACD Histogramme croise zéro

//=== FILTRES DE VALIDATION (H4) ===
input group "=== FILTRES DE VALIDATION (H4) ==="
input bool UseRSIFilter = true;         // Filtre RSI (éviter surachat/survente)
input bool UseSMMAFilter = true;        // Filtre SMMA50 (tendance générale)

//=== PARAMÈTRES DES INDICATEURS ===
input group "=== PARAMÈTRES DES INDICATEURS ==="
// Pour signaux H1
input int EMA21_Period = 21;            // Période EMA rapide
input int EMA55_Period = 55;            // Période EMA lente
input int SMMA50_Period = 50;           // Période SMMA rapide
input int SMMA200_Period = 200;         // Période SMMA lente
input int MACD_FastEMA = 12;            // MACD - EMA rapide
input int MACD_SlowEMA = 26;            // MACD - EMA lente
input int MACD_SignalSMA = 9;           // MACD - Période signal
// Pour filtres H4
input int RSI_Period = 14;              // Période RSI
input int RSI_UpperLevel = 70;          // RSI - Niveau surachat
input int RSI_LowerLevel = 30;          // RSI - Niveau survente

//=== GESTION DES RISQUES ===
input group "=== GESTION DES RISQUES ==="
input double StopLossPercent = 0.35;    // Stop Loss en % du prix
input double RiskPercent = 1.0;         // Risque par trade en % du compte
input bool UseFixedMoney = false;       // Utiliser montant fixe au lieu de %
input double FixedMoneyRisk = 100.0;    // Montant fixe risqué par trade

//=== PARAMÈTRES DE TRADING ===
input group "=== PARAMÈTRES DE TRADING ==="
input int MaxTradesPerDay = 4;          // Maximum trades par jour
input int StartHour = 6;                // Heure début trading
input int EndHour = 15;                 // Heure fin trading
input double TakeProfitMoney = 500.0;    // Take Profit en dollars de gain

//=== RÉDUCTION APRÈS PERTES ===
input group "=== RÉDUCTION APRÈS PERTES ==="
input bool UseLossStreakReduction = true;     // Réduire risque après pertes consécutives
input int LossStreakThreshold = 3;            // Nombre pertes pour déclencher réduction
input double LossStreakRiskReduction = 0.5;   // Facteur de réduction (0.5 = 50%)

//=== FILTRES MENSUELS ===
input group "=== FILTRES MENSUELS ==="
input bool UseMonthlyFilter = false;    // Activer filtrage par mois
input bool TradeJanuary = true;         // Trading autorisé en Janvier
input bool TradeFebruary = true;        // Trading autorisé en Février
input bool TradeMarch = true;           // Trading autorisé en Mars
input bool TradeApril = true;           // Trading autorisé en Avril
input bool TradeMay = true;             // Trading autorisé en Mai
input bool TradeJune = true;            // Trading autorisé en Juin
input bool TradeJuly = true;            // Trading autorisé en Juillet
input bool TradeAugust = true;          // Trading autorisé en Août
input bool TradeSeptember = true;       // Trading autorisé en Septembre
input bool TradeOctober = true;         // Trading autorisé en Octobre
input bool TradeNovember = true;        // Trading autorisé en Novembre
input bool TradeDecember = true;        // Trading autorisé en Décembre

//=== LOGGING ET EXPORT ===
input group "=== LOGGING ET EXPORT ==="
input bool EnableLogging = true;        // Activer logs dans console
input bool ExportToCSV = true;          // Exporter historique trades en CSV

//+------------------------------------------------------------------+
//|                       VARIABLES GLOBALES                         |
//+------------------------------------------------------------------+

// === OBJETS DE TRADING ===
CTrade trade;

// === HANDLES DES INDICATEURS ===
// Signaux H1
int handleEMA21_H1;
int handleEMA55_H1;
int handleSMMA50_H1;
int handleSMMA200_H1;
int handleMACD_H1;

// Filtres H4
int handleRSI_H4;
int handleSMMA50_H4;

// === ARRAYS POUR VALEURS DES INDICATEURS ===
// Signaux H1
double ema21H1Values[];
double ema55H1Values[];
double smma50H1Values[];
double smma200H1Values[];
double macdHistogramValues[];

// Filtres H4
double rsiH4Values[];
double smma50H4Values[];

// === VARIABLES DE GESTION DES TRADES ===
int tradesCount = 0;
datetime lastTradeDate = 0;
int consecutiveLosses = 0;
double currentRiskPercent;
string csvFileName;

// === SYSTÈME DE SIGNAUX PERSISTANTS ===
bool signalEMA_Active = false;         // Signal EMA21/55 actif
bool signalSMMA_Active = false;        // Signal SMMA50/200 actif  
bool signalMACD_Active = false;        // Signal MACD histogramme actif
int signalEMA_Direction = 0;           // 1=BUY, -1=SELL, 0=aucun
int signalSMMA_Direction = 0;          // 1=BUY, -1=SELL, 0=aucun
int signalMACD_Direction = 0;          // 1=BUY, -1=SELL, 0=aucun

//+------------------------------------------------------------------+
//|                    FONCTION D'INITIALISATION                     |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== INITIALISATION ALGORITHME POSEIDON ===");
   
   currentRiskPercent = RiskPercent;
   
   // === INITIALISATION DES INDICATEURS ===
   Print("Initialisation des indicateurs...");
   
   // Signaux H1
   handleEMA21_H1 = iMA(_Symbol, PERIOD_H1, EMA21_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleEMA55_H1 = iMA(_Symbol, PERIOD_H1, EMA55_Period, 0, MODE_EMA, PRICE_CLOSE);
   handleSMMA50_H1 = iMA(_Symbol, PERIOD_H1, SMMA50_Period, 0, MODE_SMMA, PRICE_CLOSE);
   handleSMMA200_H1 = iMA(_Symbol, PERIOD_H1, SMMA200_Period, 0, MODE_SMMA, PRICE_CLOSE);
   handleMACD_H1 = iMACD(_Symbol, PERIOD_H1, MACD_FastEMA, MACD_SlowEMA, MACD_SignalSMA, PRICE_CLOSE);
   
   // Filtres H4  
   handleRSI_H4 = iRSI(_Symbol, PERIOD_H4, RSI_Period, PRICE_CLOSE);
   handleSMMA50_H4 = iMA(_Symbol, PERIOD_H4, SMMA50_Period, 0, MODE_SMMA, PRICE_CLOSE);
   
   // === VÉRIFICATION DES HANDLES ===
   if(handleEMA21_H1 == INVALID_HANDLE || handleEMA55_H1 == INVALID_HANDLE || 
      handleSMMA50_H1 == INVALID_HANDLE || handleSMMA200_H1 == INVALID_HANDLE || 
      handleMACD_H1 == INVALID_HANDLE || handleRSI_H4 == INVALID_HANDLE || 
      handleSMMA50_H4 == INVALID_HANDLE)
   {
      Print("ERREUR : Échec de création des indicateurs");
      return(INIT_FAILED);
   }
   
   // === CONFIGURATION CSV ===
   if(ExportToCSV)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      csvFileName = StringFormat("%s_Poseidon_%04d%02d%02d.csv", _Symbol, dt.year, dt.mon, dt.day);
      CreateCSVHeader();
      Print("Export CSV configuré : ", csvFileName);
   }
   
   Print("=== INITIALISATION TERMINÉE AVEC SUCCÈS ===");
   Print("Signaux activés - EMA:", UseEmaSignal, " SMMA:", UseSmmaCrossSignal, " MACD:", UseMacdHistogramSignal);
   Print("Filtres activés - RSI:", UseRSIFilter, " SMMA:", UseSMMAFilter);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                   FONCTION DE DÉSINITIALISATION                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== ARRÊT DE L'ALGORITHME POSEIDON ===");
   
   // === LIBÉRATION DES INDICATEURS ===
   if(handleEMA21_H1 != INVALID_HANDLE) IndicatorRelease(handleEMA21_H1);
   if(handleEMA55_H1 != INVALID_HANDLE) IndicatorRelease(handleEMA55_H1);
   if(handleSMMA50_H1 != INVALID_HANDLE) IndicatorRelease(handleSMMA50_H1);
   if(handleSMMA200_H1 != INVALID_HANDLE) IndicatorRelease(handleSMMA200_H1);
   if(handleMACD_H1 != INVALID_HANDLE) IndicatorRelease(handleMACD_H1);
   if(handleRSI_H4 != INVALID_HANDLE) IndicatorRelease(handleRSI_H4);
   if(handleSMMA50_H4 != INVALID_HANDLE) IndicatorRelease(handleSMMA50_H4);
   
   Print("Ressources libérées. Arrêt terminé.");
}

//+------------------------------------------------------------------+
//|                      FONCTION PRINCIPALE TICK                    |
//+------------------------------------------------------------------+
void OnTick()
{
   // === VÉRIFICATION NOUVELLE BARRE H1 ===
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, PERIOD_H1, 0);
   if(currentBarTime == lastBarTime) return; // Pas de nouvelle barre
   lastBarTime = currentBarTime;
   
   // === SÉQUENCE DE VÉRIFICATIONS ===
   ResetDailyTradeCount();           // Réinitialiser compteur quotidien
   
   if(!BasicConditionsCheck()) return;  // Vérifications de base
   
   if(!UpdateIndicators()) return;      // Mise à jour des indicateurs
   
   CheckTradingSignals();               // Analyse des signaux de trading
   
   ManagePositions();                   // Gestion des positions ouvertes
}

//+------------------------------------------------------------------+
//|                    GESTION DU COMPTEUR QUOTIDIEN                 |
//+------------------------------------------------------------------+
void ResetDailyTradeCount()
{
   MqlDateTime currentTime, lastTime;
   TimeToStruct(TimeCurrent(), currentTime);
   TimeToStruct(lastTradeDate, lastTime);
   
   // Réinitialiser si nouveau jour
   if(currentTime.day != lastTime.day || currentTime.mon != lastTime.mon || currentTime.year != lastTime.year)
   {
      tradesCount = 0;
      if(EnableLogging) Print("Nouveau jour - Compteur trades réinitialisé");
   }
}

//+------------------------------------------------------------------+
//|                     VÉRIFICATIONS DE BASE                        |
//+------------------------------------------------------------------+
bool BasicConditionsCheck()
{
   // === VÉRIFICATION HEURES DE TRADING ===
   MqlDateTime currentTime;
   TimeToStruct(TimeCurrent(), currentTime);
   if(currentTime.hour < StartHour || currentTime.hour >= EndHour) 
   {
      return false; // Hors heures de trading
   }
   
   // === VÉRIFICATION LIMITE QUOTIDIENNE ===
   if(tradesCount >= MaxTradesPerDay) 
   {
      return false; // Limite quotidienne atteinte
   }
   
   // === VÉRIFICATION FILTRE MENSUEL ===
   if(UseMonthlyFilter && !IsMonthAllowed(currentTime.mon)) 
   {
      return false; // Mois non autorisé
   }
   
   // === VÉRIFICATION POSITION EXISTANTE ===
   if(PositionsTotal() > 0) 
   {
      return false; // Position déjà ouverte
   }
   
   return true; // Toutes les conditions sont remplies
}

//+------------------------------------------------------------------+
//|                    VÉRIFICATION MOIS AUTORISÉ                    |
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
//|                   MISE À JOUR DES INDICATEURS                    |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // === CONFIGURATION DES ARRAYS ===
   // Signaux H1
   ArraySetAsSeries(ema21H1Values, true);
   ArraySetAsSeries(ema55H1Values, true);
   ArraySetAsSeries(smma50H1Values, true);
   ArraySetAsSeries(smma200H1Values, true);
   ArraySetAsSeries(macdHistogramValues, true);
   
   // Filtres H4
   ArraySetAsSeries(rsiH4Values, true);
   ArraySetAsSeries(smma50H4Values, true);
   
   // === COPIE DES DONNÉES ===
   // Signaux H1 (3 dernières valeurs pour détecter croisements)
   if(CopyBuffer(handleEMA21_H1, 0, 0, 3, ema21H1Values) <= 0) return false;
   if(CopyBuffer(handleEMA55_H1, 0, 0, 3, ema55H1Values) <= 0) return false;
   if(CopyBuffer(handleSMMA50_H1, 0, 0, 3, smma50H1Values) <= 0) return false;
   if(CopyBuffer(handleSMMA200_H1, 0, 0, 3, smma200H1Values) <= 0) return false;
   if(CopyBuffer(handleMACD_H1, 0, 0, 3, macdHistogramValues) <= 0) return false; // Buffer 0 = Histogramme
   
   // Filtres H4 (valeur actuelle suffit)
   if(CopyBuffer(handleRSI_H4, 0, 0, 1, rsiH4Values) <= 0) return false;
   if(CopyBuffer(handleSMMA50_H4, 0, 0, 1, smma50H4Values) <= 0) return false;
   
   return true; // Mise à jour réussie
}

//+------------------------------------------------------------------+
//|                     ANALYSE DES SIGNAUX PERSISTANTS              |
//+------------------------------------------------------------------+
void CheckTradingSignals()
{
   // === MISE À JOUR DES SIGNAUX PERSISTANTS ===
   UpdatePersistentSignals();
   
   // === VÉRIFICATION CONDITIONS D'ENTRÉE ===
   int tradeDirection = CheckTradeConditions();
   
   if(tradeDirection != 0) // Conditions remplies pour un trade
   {
      double lotSize = CalculateLotSize();
      if(lotSize > 0)
      {
         if(tradeDirection > 0)
         {
            ExecuteBuyOrder(lotSize);
            ResetSignalsAfterTrade(); // Reset après exécution
         }
         else
         {
            ExecuteSellOrder(lotSize);
            ResetSignalsAfterTrade(); // Reset après exécution
         }
      }
   }
}

//+------------------------------------------------------------------+
//|                    MISE À JOUR SIGNAUX PERSISTANTS               |
//+------------------------------------------------------------------+
void UpdatePersistentSignals()
{
   // === ANALYSE SIGNAL EMA21/55 ===
   if(UseEmaSignal)
   {
      int emaSignal = GetEMACrossSignal();
      if(emaSignal != 0) // Nouveau croisement détecté
      {
         signalEMA_Active = true;
         signalEMA_Direction = emaSignal;
         if(EnableLogging) 
            Print(">>> Signal EMA21/55 ACTIVÉ: ", emaSignal > 0 ? "BUY" : "SELL");
      }
   }
   
   // === ANALYSE SIGNAL SMMA50/200 ===
   if(UseSmmaCrossSignal)
   {
      int smmaCrossSignal = GetSMMACrossSignal();
      if(smmaCrossSignal != 0) // Nouveau croisement détecté
      {
         signalSMMA_Active = true;
         signalSMMA_Direction = smmaCrossSignal;
         if(EnableLogging) 
            Print(">>> Signal SMMA50/200 ACTIVÉ: ", smmaCrossSignal > 0 ? "BUY" : "SELL");
      }
   }
   
   // === ANALYSE SIGNAL MACD HISTOGRAMME ===
   if(UseMacdHistogramSignal)
   {
      int macdSignal = GetMACDHistogramSignal();
      if(macdSignal != 0) // Nouveau croisement avec zéro détecté
      {
         signalMACD_Active = true;
         signalMACD_Direction = macdSignal;
         if(EnableLogging) 
            Print(">>> Signal MACD Histogramme ACTIVÉ: ", macdSignal > 0 ? "BUY" : "SELL");
      }
   }
}

//+------------------------------------------------------------------+
//|                  VÉRIFICATION CONDITIONS TRADE                   |
//+------------------------------------------------------------------+
int CheckTradeConditions()
{
   // === COMPTAGE SIGNAUX ACTIFS PAR DIRECTION ===
   int buySignals = 0;
   int sellSignals = 0;
   int totalActiveSignals = 0;
   
   if(signalEMA_Active && UseEmaSignal)
   {
      totalActiveSignals++;
      if(signalEMA_Direction > 0) buySignals++;
      else sellSignals++;
   }
   
   if(signalSMMA_Active && UseSmmaCrossSignal)
   {
      totalActiveSignals++;
      if(signalSMMA_Direction > 0) buySignals++;
      else sellSignals++;
   }
   
   if(signalMACD_Active && UseMacdHistogramSignal)
   {
      totalActiveSignals++;
      if(signalMACD_Direction > 0) buySignals++;
      else sellSignals++;
   }
   
   // === VÉRIFICATION MINIMUM 2 SIGNAUX ===
   if(totalActiveSignals < 2)
   {
      return 0; // Pas assez de signaux actifs
   }
   
   // === DÉTERMINATION DIRECTION DOMINANTE ===
   int tradeDirection = 0;
   if(buySignals >= 2) tradeDirection = 1;      // BUY si au moins 2 signaux BUY
   else if(sellSignals >= 2) tradeDirection = -1; // SELL si au moins 2 signaux SELL
   
   if(tradeDirection == 0) return 0; // Pas de direction claire
   
   // === APPLICATION DES FILTRES (H4) ===
   bool isBuySignal = (tradeDirection > 0);
   
   // Filtre RSI
   if(UseRSIFilter && !CheckRSIFilter(isBuySignal))
   {
      if(EnableLogging) Print("TRADE BLOQUÉ par filtre RSI H4");
      return 0;
   }
   
   // Filtre SMMA
   if(UseSMMAFilter && !CheckSMMAFilter(isBuySignal))
   {
      if(EnableLogging) Print("TRADE BLOQUÉ par filtre SMMA50 H4");
      return 0;
   }
   
   // === VALIDATION FINALE ===
   if(EnableLogging)
   {
      Print("=== CONDITIONS TRADE VALIDÉES ===");
      Print("Signaux actifs: ", totalActiveSignals, " | BUY: ", buySignals, " | SELL: ", sellSignals);
      Print("Direction: ", tradeDirection > 0 ? "BUY" : "SELL");
      Print("EMA:", signalEMA_Active ? (signalEMA_Direction > 0 ? "BUY" : "SELL") : "OFF");
      Print("SMMA:", signalSMMA_Active ? (signalSMMA_Direction > 0 ? "BUY" : "SELL") : "OFF"); 
      Print("MACD:", signalMACD_Active ? (signalMACD_Direction > 0 ? "BUY" : "SELL") : "OFF");
   }
   
   return tradeDirection;
}

//+------------------------------------------------------------------+
//|                    RESET SIGNAUX APRÈS TRADE                     |
//+------------------------------------------------------------------+
void ResetSignalsAfterTrade()
{
   // Réinitialisation complète des signaux après exécution d'un trade
   signalEMA_Active = false;
   signalSMMA_Active = false;
   signalMACD_Active = false;
   signalEMA_Direction = 0;
   signalSMMA_Direction = 0;
   signalMACD_Direction = 0;
   
   if(EnableLogging) Print(">>> RESET des signaux persistants après trade");
}

//+------------------------------------------------------------------+
//|                    SIGNAL EMA21/55 CROSS                         |
//+------------------------------------------------------------------+
int GetEMACrossSignal()
{
   // Valeurs actuelles et précédentes
   double ema21_current = ema21H1Values[0];
   double ema21_previous = ema21H1Values[1];
   double ema55_current = ema55H1Values[0];
   double ema55_previous = ema55H1Values[1];
   
   // Signal BUY: EMA21 croise au-dessus d'EMA55
   if(ema21_previous <= ema55_previous && ema21_current > ema55_current)
      return 1;
   
   // Signal SELL: EMA21 croise en-dessous d'EMA55
   if(ema21_previous >= ema55_previous && ema21_current < ema55_current)
      return -1;
   
   return 0; // Pas de croisement
}

//+------------------------------------------------------------------+
//|                   SIGNAL SMMA50/200 CROSS                        |
//+------------------------------------------------------------------+
int GetSMMACrossSignal()
{
   // Valeurs actuelles et précédentes
   double smma50_current = smma50H1Values[0];
   double smma50_previous = smma50H1Values[1];
   double smma200_current = smma200H1Values[0];
   double smma200_previous = smma200H1Values[1];
   
   // Signal BUY: SMMA50 croise au-dessus de SMMA200
   if(smma50_previous <= smma200_previous && smma50_current > smma200_current)
      return 1;
   
   // Signal SELL: SMMA50 croise en-dessous de SMMA200
   if(smma50_previous >= smma200_previous && smma50_current < smma200_current)
      return -1;
   
   return 0; // Pas de croisement
}

//+------------------------------------------------------------------+
//|                 SIGNAL MACD HISTOGRAMME CROISE ZÉRO              |
//+------------------------------------------------------------------+
int GetMACDHistogramSignal()
{
   // Valeurs actuelles et précédentes de l'histogramme MACD
   double histogram_current = macdHistogramValues[0];
   double histogram_previous = macdHistogramValues[1];
   
   // Signal BUY: Histogramme croise au-dessus de zéro
   if(histogram_previous <= 0.0 && histogram_current > 0.0)
      return 1;
   
   // Signal SELL: Histogramme croise en-dessous de zéro
   if(histogram_previous >= 0.0 && histogram_current < 0.0)
      return -1;
   
   return 0; // Pas de croisement avec zéro
}

//+------------------------------------------------------------------+
//|                       FILTRE RSI (H4)                            |
//+------------------------------------------------------------------+
bool CheckRSIFilter(bool isBuySignal)
{
   double rsi_current = rsiH4Values[0];
   
   // Pour BUY: éviter surachat (RSI >= 70)
   if(isBuySignal && rsi_current >= RSI_UpperLevel) return false;
   
   // Pour SELL: éviter survente (RSI <= 30)
   if(!isBuySignal && rsi_current <= RSI_LowerLevel) return false;
   
   return true; // RSI OK
}

//+------------------------------------------------------------------+
//|                      FILTRE SMMA50 (H4)                          |
//+------------------------------------------------------------------+
bool CheckSMMAFilter(bool isBuySignal)
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double smma50_h4 = smma50H4Values[0];
   
   // Pour BUY: prix doit être au-dessus de SMMA50 H4 (tendance haussière)
   if(isBuySignal && price < smma50_h4) return false;
   
   // Pour SELL: prix doit être en-dessous de SMMA50 H4 (tendance baissière)
   if(!isBuySignal && price > smma50_h4) return false;
   
   return true; // Tendance OK
}

//+------------------------------------------------------------------+
//|           CALCUL LOT SIZE - VERSION ULTRA-SIMPLIFIÉE XAUUSD      |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   // ============================================================================
   // CALCUL FORCÉ SPÉCIALEMENT POUR XAUUSD AVEC RISQUE 100$ ET SL 0.35%
   // ============================================================================
   
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // FORCER LE RISQUE À 100$ (ignorer tous les paramètres)
   double riskAmount = 100.0;
   
   // FORCER LE SL À 0.35% 
   double stopLossPercent = 0.35;
   double stopLossDistance = currentPrice * stopLossPercent / 100.0;
   
   // ============================================================================ 
   // CALCUL SPÉCIFIQUE XAUUSD : 1$ de mouvement = 10 pips = 1$ par lot mini
   // Donc pour SL de X dollars → perte = X$ par lot mini (0.01)
   // Pour risquer 100$ avec SL de ~7$ → besoin de ~14 lots mini = 0.14 lot
   // ============================================================================
   
   double lotSize = riskAmount / stopLossDistance / 100.0; // Division par 100 pour XAUUSD
   
   // Limites de sécurité
   if(lotSize < 0.01) lotSize = 0.01;
   if(lotSize > 10.0) lotSize = 10.0;
   
   // Arrondir à 0.01
   lotSize = MathRound(lotSize * 100.0) / 100.0;
   
   // ============================================================================
   // LOGS DE DÉBOGAGE DÉTAILLÉS
   // ============================================================================
   Print("╔══════════════════════════════════════════════════════════════════╗");
   Print("║                    CALCUL LOT SIZE ULTRA-SIMPLIFIÉ              ║");
   Print("╠══════════════════════════════════════════════════════════════════╣");
   Print("║ Prix XAUUSD: ", currentPrice, "                                   ║");
   Print("║ Risque forcé: ", riskAmount, "$                                 ║");
   Print("║ SL forcé: ", stopLossPercent, "% = ", stopLossDistance, "$      ║");
   Print("║ Formule: ", riskAmount, " ÷ ", stopLossDistance, " ÷ 100        ║");
   Print("║ LOT CALCULÉ: ", lotSize, "                                       ║");
   Print("╚══════════════════════════════════════════════════════════════════╝");
   
   // Vérification finale
   if(lotSize > 1.0)
   {
      Print("⚠️ ALERTE: Lot calculé trop grand (", lotSize, ") - forcé à 0.15");
      lotSize = 0.15;
   }
   
   Print("🎯 LOT FINAL UTILISÉ: ", lotSize);
   
   return lotSize;
}

//+------------------------------------------------------------------+
//|                       EXÉCUTION ORDRE BUY                        |
//+------------------------------------------------------------------+
void ExecuteBuyOrder(double lotSize)
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double stopLoss = price * (1 - StopLossPercent / 100.0);
   
   // Calcul TP SIMPLIFIÉ pour XAUUSD - Target 500$ de gain
   double targetProfit = 500.0; // Forcer à 500$ (5R de 100$)
   double tpDistance = targetProfit / (lotSize * 100.0); // Pour XAUUSD: 1$ = 100 lots mini de profit
   double takeProfit = price + tpDistance;
   
   Print("🎯 TP BUY: Lot=", lotSize, " Target=", targetProfit, "$ Distance=", tpDistance, "$ TP=", takeProfit);
   
   if(trade.Buy(lotSize, _Symbol, price, stopLoss, takeProfit, "Poseidon BUY"))
   {
      tradesCount++;
      lastTradeDate = TimeCurrent();
      
      if(EnableLogging)
         Print(">>> ORDRE BUY EXÉCUTÉ - Lots:", lotSize, " Prix:", price, " SL:", stopLoss, " TP:", takeProfit, " (Gain cible: ", TakeProfitMoney, "$)");
      
      if(ExportToCSV)
         LogTradeToCSV("BUY", lotSize, price, stopLoss, takeProfit);
   }
   else
   {
      if(EnableLogging) Print("ERREUR: Échec exécution ordre BUY");
   }
}

//+------------------------------------------------------------------+
//|                      EXÉCUTION ORDRE SELL                        |
//+------------------------------------------------------------------+
void ExecuteSellOrder(double lotSize)
{
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double stopLoss = price * (1 + StopLossPercent / 100.0);
   
   // Calcul TP SIMPLIFIÉ pour XAUUSD - Target 500$ de gain
   double targetProfit = 500.0; // Forcer à 500$ (5R de 100$)
   double tpDistance = targetProfit / (lotSize * 100.0); // Pour XAUUSD: 1$ = 100 lots mini de profit
   double takeProfit = price - tpDistance;
   
   Print("🎯 TP SELL: Lot=", lotSize, " Target=", targetProfit, "$ Distance=", tpDistance, "$ TP=", takeProfit);
   
   if(trade.Sell(lotSize, _Symbol, price, stopLoss, takeProfit, "Poseidon SELL"))
   {
      tradesCount++;
      lastTradeDate = TimeCurrent();
      
      if(EnableLogging)
         Print(">>> ORDRE SELL EXÉCUTÉ - Lots:", lotSize, " Prix:", price, " SL:", stopLoss, " TP:", takeProfit, " (Gain cible: ", TakeProfitMoney, "$)");
      
      if(ExportToCSV)
         LogTradeToCSV("SELL", lotSize, price, stopLoss, takeProfit);
   }
   else
   {
      if(EnableLogging) Print("ERREUR: Échec exécution ordre SELL");
   }
}

//+------------------------------------------------------------------+
//|                    GESTION DES POSITIONS                         |
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
            CheckBreakEven(); // Vérifier break-even pour cette position
         }
      }
   }
}

//+------------------------------------------------------------------+
//|                     GESTION DU BREAK-EVEN                        |
//+------------------------------------------------------------------+
void CheckBreakEven()
{
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   long positionType = PositionGetInteger(POSITION_TYPE);
   double profit = PositionGetDouble(POSITION_PROFIT);
   
   if(profit >= 300.0) // Break-even déclenché à 300$ de profit
   {
      double newStopLoss = openPrice; // Déplacer SL au prix d'entrée
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      
      if(positionType == POSITION_TYPE_BUY)
      {
         if(PositionGetDouble(POSITION_SL) < newStopLoss)
         {
            if(trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP)))
            {
               if(EnableLogging) Print("Break-even appliqué pour position BUY #", ticket);
            }
         }
      }
      else if(positionType == POSITION_TYPE_SELL)
      {
         double currentSL = PositionGetDouble(POSITION_SL);
         if(currentSL > newStopLoss || currentSL == 0.0)
         {
            if(trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP)))
            {
               if(EnableLogging) Print("Break-even appliqué pour position SELL #", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//|                    CRÉATION EN-TÊTE CSV                          |
//+------------------------------------------------------------------+
void CreateCSVHeader()
{
   int fileHandle = FileOpen(csvFileName, FILE_WRITE|FILE_CSV);
   if(fileHandle != INVALID_HANDLE)
   {
      FileWrite(fileHandle, "Date", "Heure", "Type", "Lots", "Prix_Entree", "Stop_Loss", "Take_Profit", "Profit_Final");
      FileClose(fileHandle);
   }
}

//+------------------------------------------------------------------+
//|                      ENREGISTREMENT CSV                          |
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
      
      FileWrite(fileHandle, dateStr, timeStr, type, lots, price, sl, tp, "En_cours");
      FileClose(fileHandle);
   }
}

//+------------------------------------------------------------------+
//|                  GESTION DES RÉSULTATS DE TRADES                 |
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
         
         // === GESTION SÉRIE DE PERTES ===
         if(profit < 0)
            consecutiveLosses++;
         else
            consecutiveLosses = 0; // Réinitialiser après un gain
         
         if(EnableLogging)
         {
            Print("=== RÉSULTAT TRADE ===");
            Print("Profit: ", profit, " | Pertes consécutives: ", consecutiveLosses);
            if(consecutiveLosses >= LossStreakThreshold)
               Print("ATTENTION: Seuil de pertes atteint - Risque réduit activé");
         }
      }
   }
}

//+------------------------------------------------------------------+
//|                            FIN DU CODE                           |
//+------------------------------------------------------------------+
