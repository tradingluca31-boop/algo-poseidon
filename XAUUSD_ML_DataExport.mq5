//+------------------------------------------------------------------+
//|                                    XAUUSD_ML_DataExport.mq5      |
//|  Script pour exporter 10 ans de données XAUUSD H1 avec          |
//|  tous les indicateurs techniques pour Machine Learning          |
//|  Version: 1.0 - 2025-10-09                                       |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

//======================== INPUTS ========================
input int    InpYearsBack        = 10;      // Nombre d'années à exporter
input string InpSymbol           = "XAUUSD"; // Symbole à analyser
input ENUM_TIMEFRAMES InpTF      = PERIOD_H1; // Timeframe
input bool   InpIncludeTarget    = true;    // Calculer WIN/LOSS (target)
input double InpSL_Percent       = 0.35;    // SL en % du prix d'entrée
input double InpTP_Percent       = 1.75;    // TP en % du prix d'entrée
input int    InpForwardBars      = 48;      // Barres à regarder pour SL/TP

// Indicateurs MACD custom
input int InpMACD_Fast   = 20;  // MACD: SMA rapide
input int InpMACD_Slow   = 35;  // MACD: SMA lente
input int InpMACD_Signal = 15;  // MACD: SMA signal

//======================== STRUCTURE DONNÉES ========================
struct DataRow {
    datetime time;
    double open, high, low, close, volume;

    // Indicateurs
    double ema21, ema55;
    double macd, macd_signal, macd_hist;
    double smma50, smma200;
    double rsi14, rsi28;
    double atr14, atr28;
    double adx14, di_plus, di_minus;
    double stoch_k, stoch_d;
    double bb_upper, bb_middle, bb_lower, bb_width;
    double cci20;
    double volatility;

    // Signaux
    int signal_ema;
    int signal_macd;
    int signal_smma;
    int signal_score;

    // Features temporelles
    int hour;
    int day_of_week;
    int month;
    int year;
    int in_session;

    // Target ML
    int target;
};

//======================== VARIABLES GLOBALES ========================
string sym;
int dig;
double pt;

// Handles indicateurs
int hEMA21, hEMA55;
int hSMAfast, hSMAslow;
int hSMMA50, hSMMA200;
int hRSI14, hRSI28;
int hATR14, hATR28;
int hADX14;
int hStoch;
int hBB;
int hCCI;

//======================== FONCTION PRINCIPALE ========================
void OnStart()
{
    Print("=== DÉBUT EXPORT DONNÉES ML XAUUSD ===");

    sym = InpSymbol;
    dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
    pt = SymbolInfoDouble(sym, SYMBOL_POINT);

    // Calculer la date de début
    datetime endDate = TimeCurrent();
    datetime startDate = endDate - (InpYearsBack * 365 * 86400);

    PrintFormat("Symbole: %s | TF: %s | Période: %s à %s",
                sym, EnumToString(InpTF),
                TimeToString(startDate), TimeToString(endDate));

    // Initialiser les indicateurs
    if(!InitIndicators()) {
        Print("ERREUR: Échec initialisation indicateurs");
        ReleaseIndicators();
        return;
    }

    Print("✅ Indicateurs initialisés avec succès");

    // Copier les données OHLCV
    datetime timeArray[];
    double openArray[], highArray[], lowArray[], closeArray[];
    long volumeArray[];

    ArraySetAsSeries(timeArray, true);
    ArraySetAsSeries(openArray, true);
    ArraySetAsSeries(highArray, true);
    ArraySetAsSeries(lowArray, true);
    ArraySetAsSeries(closeArray, true);
    ArraySetAsSeries(volumeArray, true);

    int totalBars = CopyTime(sym, InpTF, startDate, endDate, timeArray);
    if(totalBars <= 0) {
        Print("ERREUR: Impossible de copier les données historiques");
        ReleaseIndicators();
        return;
    }

    CopyOpen(sym, InpTF, startDate, endDate, openArray);
    CopyHigh(sym, InpTF, startDate, endDate, highArray);
    CopyLow(sym, InpTF, startDate, endDate, lowArray);
    CopyClose(sym, InpTF, startDate, endDate, closeArray);
    CopyTickVolume(sym, InpTF, startDate, endDate, volumeArray);

    PrintFormat("✅ %d barres chargées", totalBars);

    // Préparer le fichier CSV
    string fileName = StringFormat("%s_ML_Data_%dY_%s.csv",
                                   sym, InpYearsBack,
                                   TimeToString(TimeCurrent(), TIME_DATE));

    int fileHandle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, 0, CP_UTF8);
    if(fileHandle == INVALID_HANDLE) {
        Print("ERREUR: Impossible de créer le fichier CSV");
        ReleaseIndicators();
        return;
    }

    Print("✅ Fichier CSV créé: ", fileName);

    // Écrire l'en-tête
    WriteCSVHeader(fileHandle);

    // Boucle principale sur les barres
    int exportedCount = 0;
    int progressStep = MathMax(1, totalBars / 20); // Afficher progrès tous les 5%

    for(int i = totalBars - 1; i >= InpForwardBars; i--) {

        DataRow row;

        // Données OHLCV
        row.time = timeArray[i];
        row.open = openArray[i];
        row.high = highArray[i];
        row.low = lowArray[i];
        row.close = closeArray[i];
        row.volume = (double)volumeArray[i];

        // Calculer tous les indicateurs
        if(!CalculateIndicators(i, row)) {
            continue; // Skip si erreur
        }

        // Calculer les signaux
        CalculateSignals(row);

        // Features temporelles
        CalculateTimeFeatures(row.time, row);

        // Target ML (WIN/LOSS)
        if(InpIncludeTarget) {
            row.target = SimulateTrade(i, row.close, row.signal_score,
                                      closeArray, highArray, lowArray);
        } else {
            row.target = -1;
        }

        // Écrire dans CSV
        WriteCSVRow(fileHandle, row);
        exportedCount++;

        // Afficher progression
        if(i % progressStep == 0) {
            double progress = 100.0 * (totalBars - i) / totalBars;
            PrintFormat("Progression: %.1f%% (%d/%d barres)", progress, totalBars - i, totalBars);
        }
    }

    FileClose(fileHandle);
    ReleaseIndicators();

    PrintFormat("=== EXPORT TERMINÉ: %d lignes exportées ===", exportedCount);
    PrintFormat("📁 Fichier: MQL5/Files/Common/%s", fileName);
}

//======================== INITIALISATION INDICATEURS ========================
bool InitIndicators()
{
    hEMA21 = iMA(sym, InpTF, 21, 0, MODE_EMA, PRICE_CLOSE);
    hEMA55 = iMA(sym, InpTF, 55, 0, MODE_EMA, PRICE_CLOSE);

    hSMAfast = iMA(sym, InpTF, InpMACD_Fast, 0, MODE_SMA, PRICE_CLOSE);
    hSMAslow = iMA(sym, InpTF, InpMACD_Slow, 0, MODE_SMA, PRICE_CLOSE);

    hSMMA50 = iMA(sym, InpTF, 50, 0, MODE_SMMA, PRICE_CLOSE);
    hSMMA200 = iMA(sym, InpTF, 200, 0, MODE_SMMA, PRICE_CLOSE);

    hRSI14 = iRSI(sym, InpTF, 14, PRICE_CLOSE);
    hRSI28 = iRSI(sym, InpTF, 28, PRICE_CLOSE);

    hATR14 = iATR(sym, InpTF, 14);
    hATR28 = iATR(sym, InpTF, 28);

    hADX14 = iADX(sym, InpTF, 14);

    hStoch = iStochastic(sym, InpTF, 14, 3, 3, MODE_SMA, STO_LOWHIGH);

    hBB = iBands(sym, InpTF, 20, 0, 2.0, PRICE_CLOSE);

    hCCI = iCCI(sym, InpTF, 20, PRICE_TYPICAL);

    // Vérifier tous les handles
    if(hEMA21 == INVALID_HANDLE || hEMA55 == INVALID_HANDLE ||
       hSMAfast == INVALID_HANDLE || hSMAslow == INVALID_HANDLE ||
       hSMMA50 == INVALID_HANDLE || hSMMA200 == INVALID_HANDLE ||
       hRSI14 == INVALID_HANDLE || hRSI28 == INVALID_HANDLE ||
       hATR14 == INVALID_HANDLE || hATR28 == INVALID_HANDLE ||
       hADX14 == INVALID_HANDLE || hStoch == INVALID_HANDLE ||
       hBB == INVALID_HANDLE || hCCI == INVALID_HANDLE) {
        return false;
    }

    return true;
}

//======================== LIBÉRATION INDICATEURS ========================
void ReleaseIndicators()
{
    if(hEMA21 != INVALID_HANDLE) IndicatorRelease(hEMA21);
    if(hEMA55 != INVALID_HANDLE) IndicatorRelease(hEMA55);
    if(hSMAfast != INVALID_HANDLE) IndicatorRelease(hSMAfast);
    if(hSMAslow != INVALID_HANDLE) IndicatorRelease(hSMAslow);
    if(hSMMA50 != INVALID_HANDLE) IndicatorRelease(hSMMA50);
    if(hSMMA200 != INVALID_HANDLE) IndicatorRelease(hSMMA200);
    if(hRSI14 != INVALID_HANDLE) IndicatorRelease(hRSI14);
    if(hRSI28 != INVALID_HANDLE) IndicatorRelease(hRSI28);
    if(hATR14 != INVALID_HANDLE) IndicatorRelease(hATR14);
    if(hATR28 != INVALID_HANDLE) IndicatorRelease(hATR28);
    if(hADX14 != INVALID_HANDLE) IndicatorRelease(hADX14);
    if(hStoch != INVALID_HANDLE) IndicatorRelease(hStoch);
    if(hBB != INVALID_HANDLE) IndicatorRelease(hBB);
    if(hCCI != INVALID_HANDLE) IndicatorRelease(hCCI);
}

//======================== CALCUL INDICATEURS ========================
bool CalculateIndicators(int shift, DataRow &row)
{
    double buffer[];
    ArraySetAsSeries(buffer, true);

    // EMA21
    if(CopyBuffer(hEMA21, 0, shift, 1, buffer) < 1) return false;
    row.ema21 = buffer[0];

    // EMA55
    if(CopyBuffer(hEMA55, 0, shift, 1, buffer) < 1) return false;
    row.ema55 = buffer[0];

    // MACD custom (SMA-based)
    if(!CalculateMACD_SMA(shift, row.macd, row.macd_signal, row.macd_hist)) return false;

    // SMMA50
    if(CopyBuffer(hSMMA50, 0, shift, 1, buffer) < 1) return false;
    row.smma50 = buffer[0];

    // SMMA200
    if(CopyBuffer(hSMMA200, 0, shift, 1, buffer) < 1) return false;
    row.smma200 = buffer[0];

    // RSI14
    if(CopyBuffer(hRSI14, 0, shift, 1, buffer) < 1) return false;
    row.rsi14 = buffer[0];

    // RSI28
    if(CopyBuffer(hRSI28, 0, shift, 1, buffer) < 1) return false;
    row.rsi28 = buffer[0];

    // ATR14
    if(CopyBuffer(hATR14, 0, shift, 1, buffer) < 1) return false;
    row.atr14 = buffer[0];

    // ATR28
    if(CopyBuffer(hATR28, 0, shift, 1, buffer) < 1) return false;
    row.atr28 = buffer[0];

    // ADX14 (buffer 0 = ADX, 1 = DI+, 2 = DI-)
    if(CopyBuffer(hADX14, 0, shift, 1, buffer) < 1) return false;
    row.adx14 = buffer[0];

    if(CopyBuffer(hADX14, 1, shift, 1, buffer) < 1) return false;
    row.di_plus = buffer[0];

    if(CopyBuffer(hADX14, 2, shift, 1, buffer) < 1) return false;
    row.di_minus = buffer[0];

    // Stochastic (buffer 0 = %K, 1 = %D)
    if(CopyBuffer(hStoch, 0, shift, 1, buffer) < 1) return false;
    row.stoch_k = buffer[0];

    if(CopyBuffer(hStoch, 1, shift, 1, buffer) < 1) return false;
    row.stoch_d = buffer[0];

    // Bollinger Bands (0 = upper, 1 = middle, 2 = lower)
    if(CopyBuffer(hBB, 0, shift, 1, buffer) < 1) return false;
    row.bb_upper = buffer[0];

    if(CopyBuffer(hBB, 1, shift, 1, buffer) < 1) return false;
    row.bb_middle = buffer[0];

    if(CopyBuffer(hBB, 2, shift, 1, buffer) < 1) return false;
    row.bb_lower = buffer[0];

    row.bb_width = row.bb_upper - row.bb_lower;

    // CCI20
    if(CopyBuffer(hCCI, 0, shift, 1, buffer) < 1) return false;
    row.cci20 = buffer[0];

    // Volatilité historique (écart-type des returns sur 20 périodes)
    row.volatility = CalculateVolatility(shift);

    return true;
}

//======================== MACD CUSTOM SMA ========================
bool CalculateMACD_SMA(int shift, double &macd, double &signal, double &hist)
{
    int need = MathMax(InpMACD_Slow, InpMACD_Signal) + 5;
    double fast[], slow[];
    ArraySetAsSeries(fast, true);
    ArraySetAsSeries(slow, true);

    if(CopyBuffer(hSMAfast, 0, shift, need, fast) < need) return false;
    if(CopyBuffer(hSMAslow, 0, shift, need, slow) < need) return false;

    // MACD = Fast - Slow
    double macdArr[];
    ArrayResize(macdArr, need);
    for(int i = 0; i < need; i++) {
        macdArr[i] = fast[i] - slow[i];
    }

    // Signal = SMA du MACD sur InpMACD_Signal périodes
    double sigArr[];
    ArrayResize(sigArr, need);
    int p = InpMACD_Signal;
    double acc = 0;

    for(int i = 0; i < need; i++) {
        acc += macdArr[i];
        if(i >= p) acc -= macdArr[i - p];
        if(i >= p - 1) sigArr[i] = acc / p;
        else sigArr[i] = macdArr[i];
    }

    macd = macdArr[0];
    signal = sigArr[0];
    hist = macd - signal;

    return true;
}

//======================== VOLATILITÉ ========================
double CalculateVolatility(int shift)
{
    double closes[];
    ArraySetAsSeries(closes, true);

    int period = 20;
    if(CopyClose(sym, InpTF, shift, period + 1, closes) < period + 1) return 0.0;

    // Calculer les returns
    double returns[];
    ArrayResize(returns, period);

    for(int i = 0; i < period; i++) {
        if(closes[i + 1] == 0) return 0.0;
        returns[i] = MathLog(closes[i] / closes[i + 1]);
    }

    // Calculer la moyenne
    double mean = 0;
    for(int i = 0; i < period; i++) {
        mean += returns[i];
    }
    mean /= period;

    // Calculer l'écart-type
    double variance = 0;
    for(int i = 0; i < period; i++) {
        variance += MathPow(returns[i] - mean, 2);
    }
    variance /= period;

    double stdDev = MathSqrt(variance);

    // Annualiser (H1 = 24 * 365 périodes par an)
    double annualized = stdDev * MathSqrt(24.0 * 365.0);

    return annualized;
}

//======================== CALCUL SIGNAUX ========================
void CalculateSignals(DataRow &row)
{
    // Signal EMA: +1 si EMA21 > EMA55, -1 si EMA21 < EMA55
    if(row.ema21 > row.ema55) row.signal_ema = 1;
    else if(row.ema21 < row.ema55) row.signal_ema = -1;
    else row.signal_ema = 0;

    // Signal MACD: +1 si hist > 0, -1 si hist < 0
    if(row.macd_hist > 0) row.signal_macd = 1;
    else if(row.macd_hist < 0) row.signal_macd = -1;
    else row.signal_macd = 0;

    // Signal SMMA: +1 si close > SMMA50, -1 si close < SMMA50
    if(row.close > row.smma50) row.signal_smma = 1;
    else if(row.close < row.smma50) row.signal_smma = -1;
    else row.signal_smma = 0;

    // Score total
    row.signal_score = row.signal_ema + row.signal_macd + row.signal_smma;
}

//======================== FEATURES TEMPORELLES ========================
void CalculateTimeFeatures(datetime time, DataRow &row)
{
    MqlDateTime dt;
    TimeToStruct(time, dt);

    row.hour = dt.hour;
    row.day_of_week = dt.day_of_week;
    row.month = dt.mon;
    row.year = dt.year;

    // Session trading 6h-15h
    row.in_session = (dt.hour >= 6 && dt.hour < 15) ? 1 : 0;
}

//======================== SIMULATION TRADE (TARGET ML) ========================
int SimulateTrade(int shift, double close, int signalScore,
                  const double &closeArr[], const double &highArr[], const double &lowArr[])
{
    // Seuil pour déclencher un trade: score >= 2 (BUY) ou <= -2 (SELL)
    if(signalScore < 2 && signalScore > -2) return -1; // Pas de signal

    int direction = (signalScore >= 2) ? 1 : -1; // 1=BUY, -1=SELL
    double entry = close;

    // Calculer SL et TP
    double sl, tp;
    if(direction > 0) {
        sl = entry * (1.0 - InpSL_Percent / 100.0);
        tp = entry * (1.0 + InpTP_Percent / 100.0);
    } else {
        sl = entry * (1.0 + InpSL_Percent / 100.0);
        tp = entry * (1.0 - InpTP_Percent / 100.0);
    }

    // Regarder les N barres suivantes (InpForwardBars)
    for(int i = shift - 1; i >= MathMax(0, shift - InpForwardBars); i--) {
        double h = highArr[i];
        double l = lowArr[i];

        if(direction > 0) {
            // BUY: vérifier si SL ou TP touché
            if(l <= sl) return 0; // LOSS
            if(h >= tp) return 1; // WIN
        } else {
            // SELL: vérifier si SL ou TP touché
            if(h >= sl) return 0; // LOSS
            if(l <= tp) return 1; // WIN
        }
    }

    return -1; // Ni SL ni TP touché = invalide
}

//======================== ÉCRITURE CSV ========================
void WriteCSVHeader(int handle)
{
    string header = "time,open,high,low,close,volume,";
    header += "ema21,ema55,macd,macd_signal,macd_hist,smma50,smma200,";
    header += "rsi14,rsi28,atr14,atr28,adx14,di_plus,di_minus,";
    header += "stoch_k,stoch_d,bb_upper,bb_middle,bb_lower,bb_width,cci20,volatility,";
    header += "signal_ema,signal_macd,signal_smma,signal_score,";
    header += "hour,day_of_week,month,year,in_session,target";

    FileWrite(handle, header);
}

void WriteCSVRow(int handle, const DataRow &row)
{
    string line = "";
    line += TimeToString(row.time, TIME_DATE | TIME_MINUTES) + ",";
    line += DoubleToString(row.open, dig) + ",";
    line += DoubleToString(row.high, dig) + ",";
    line += DoubleToString(row.low, dig) + ",";
    line += DoubleToString(row.close, dig) + ",";
    line += DoubleToString(row.volume, 0) + ",";

    line += DoubleToString(row.ema21, dig) + ",";
    line += DoubleToString(row.ema55, dig) + ",";
    line += DoubleToString(row.macd, 5) + ",";
    line += DoubleToString(row.macd_signal, 5) + ",";
    line += DoubleToString(row.macd_hist, 5) + ",";
    line += DoubleToString(row.smma50, dig) + ",";
    line += DoubleToString(row.smma200, dig) + ",";

    line += DoubleToString(row.rsi14, 2) + ",";
    line += DoubleToString(row.rsi28, 2) + ",";
    line += DoubleToString(row.atr14, dig) + ",";
    line += DoubleToString(row.atr28, dig) + ",";
    line += DoubleToString(row.adx14, 2) + ",";
    line += DoubleToString(row.di_plus, 2) + ",";
    line += DoubleToString(row.di_minus, 2) + ",";

    line += DoubleToString(row.stoch_k, 2) + ",";
    line += DoubleToString(row.stoch_d, 2) + ",";
    line += DoubleToString(row.bb_upper, dig) + ",";
    line += DoubleToString(row.bb_middle, dig) + ",";
    line += DoubleToString(row.bb_lower, dig) + ",";
    line += DoubleToString(row.bb_width, dig) + ",";
    line += DoubleToString(row.cci20, 2) + ",";
    line += DoubleToString(row.volatility, 4) + ",";

    line += IntegerToString(row.signal_ema) + ",";
    line += IntegerToString(row.signal_macd) + ",";
    line += IntegerToString(row.signal_smma) + ",";
    line += IntegerToString(row.signal_score) + ",";

    line += IntegerToString(row.hour) + ",";
    line += IntegerToString(row.day_of_week) + ",";
    line += IntegerToString(row.month) + ",";
    line += IntegerToString(row.year) + ",";
    line += IntegerToString(row.in_session) + ",";
    line += IntegerToString(row.target);

    FileWrite(handle, line);
}
//+------------------------------------------------------------------+
