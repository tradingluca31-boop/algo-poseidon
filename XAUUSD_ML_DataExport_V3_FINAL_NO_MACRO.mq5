//+------------------------------------------------------------------+
//|                    XAUUSD_ML_DataExport_V3_FINAL.mq5            |
//|  Export ML avec indicateurs Poseidon + ATR/ADX + H4             |
//|  DXY/VIX/US10Y seront ajoutes par Python depuis Yahoo Finance   |
//|  Version: 3.0 FINAL - 2025-10-12                                |
//+------------------------------------------------------------------+
#property script_show_inputs

//======================== INPUTS ========================
input int    InpYearsBack        = 20;      // Nombre d'annees a exporter
input string InpSymbol           = "XAUUSD"; // Symbole
input ENUM_TIMEFRAMES InpTF      = PERIOD_H1; // Timeframe
input bool   InpIncludeTarget    = true;    // Calculer target
input double InpSL_ATR_Multiplier = 1.5;    // SL = ATR14 * multiplier
input double InpTP_ATR_Multiplier = 4.0;    // TP = ATR14 * multiplier (RR 2.67)
input bool   InpUseBreakEven     = true;    // Activer Break Even a 1R
input int    InpForwardBars      = 180;     // Barres a regarder (7.5 jours)
input int    InpFutureBars       = 24;      // Predire mouvement sur 24H

// Indicateurs MACD custom (Poseidon)
input int InpMACD_Fast   = 20;
input int InpMACD_Slow   = 35;
input int InpMACD_Signal = 15;

// RSI H4 (Poseidon avec tes parametres)
input int InpRSIPeriod = 12;              // Periode RSI H4
input int InpRSIOverbought = 80;          // Seuil surachat RSI H4
input int InpRSIOversold = 25;            // Seuil survente RSI H4

//======================== STRUCTURE DONNEES ========================
struct DataRow {
    datetime time;
    double open, high, low, close, volume;

    // Indicateurs H1 (Poseidon)
    double ema21, ema55;
    double macd, macd_signal, macd_hist;
    double smma50, smma200;

    // NOUVEAUX: ATR et ADX H1
    double atr14;
    double adx14;
    double di_plus, di_minus;

    // NOUVEAUX: Indicateurs H4 (Poseidon)
    double smma50_h4;
    double rsi_h4;
    int trend_h4;              // 1=haussiere, -1=baissiere, 0=neutre

    // Signaux (Poseidon)
    int signal_ema;
    int signal_macd;
    int signal_smma;
    int signal_score;

    // Filtre RSI H4
    int rsi_filter;            // 0=OK, 1=Overbought, -1=Oversold

    // Filtre ADX (market regime)
    int adx_regime;            // 0=Range (ADX<20), 1=Tendance (20-40), 2=Forte (>40)

    // Features temporelles
    int hour;
    int day_of_week;
    int month;
    int year;
    int in_session;

    // Target ML
    int target_binary;
    double target_pct_change;
    double sl_price;
    double tp_price;
};

//======================== VARIABLES GLOBALES ========================
string sym;
int dig;
double pt;

// Handles indicateurs H1 (Poseidon)
int hEMA21, hEMA55;
int hSMAfast, hSMAslow;
int hSMMA50_H1, hSMMA200_H1;

// NOUVEAUX: Handles ATR et ADX H1
int hATR14;
int hADX14;

// NOUVEAUX: Handles H4 (Poseidon)
int hSMMA50_H4;
int hRSI_H4;

//======================== FONCTION PRINCIPALE ========================
void OnStart()
{
    Print("=== DEBUT EXPORT ML V3.0 FINAL - POSEIDON + ATR/ADX + H4 ===");

    sym = InpSymbol;
    dig = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
    pt = SymbolInfoDouble(sym, SYMBOL_POINT);

    datetime endDate = TimeCurrent();
    datetime startDate = endDate - (InpYearsBack * 365 * 86400);

    PrintFormat("Symbole: %s | TF: %s", sym, EnumToString(InpTF));
    PrintFormat("Periode: %s a %s", TimeToString(startDate), TimeToString(endDate));
    PrintFormat("SL = ATR14 x %.1f | TP = ATR14 x %.1f", InpSL_ATR_Multiplier, InpTP_ATR_Multiplier);
    PrintFormat("RSI H4: Periode=%d, Overbought=%d, Oversold=%d", InpRSIPeriod, InpRSIOverbought, InpRSIOversold);
    Print("NOUVEAUX: ATR14, ADX14, SMMA50 H4, RSI H4");
    Print("NOTE: DXY/VIX/US10Y seront ajoutes par script Python depuis Yahoo Finance");

    // Initialiser indicateurs
    if(!InitIndicators()) {
        Print("ERREUR: Echec initialisation indicateurs");
        ReleaseIndicators();
        return;
    }

    Print("OK: Indicateurs initialises (H1 + H4)");

    // Copier donnees OHLCV
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
        Print("ERREUR: Impossible de copier les donnees");
        ReleaseIndicators();
        return;
    }

    CopyOpen(sym, InpTF, startDate, endDate, openArray);
    CopyHigh(sym, InpTF, startDate, endDate, highArray);
    CopyLow(sym, InpTF, startDate, endDate, lowArray);
    CopyClose(sym, InpTF, startDate, endDate, closeArray);
    CopyTickVolume(sym, InpTF, startDate, endDate, volumeArray);

    PrintFormat("OK: %d barres chargees", totalBars);

    // Preparer fichier CSV
    string fileName = StringFormat("%s_ML_Data_V3_FINAL_%dY.csv", sym, InpYearsBack);

    int fileHandle = FileOpen(fileName, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, 0, CP_UTF8);
    if(fileHandle == INVALID_HANDLE) {
        Print("ERREUR: Impossible de creer le fichier CSV");
        ReleaseIndicators();
        return;
    }

    Print("OK: Fichier CSV cree: ", fileName);

    // Ecrire en-tete
    WriteCSVHeader(fileHandle);

    // Boucle principale
    int exportedCount = 0;
    int progressStep = MathMax(1, totalBars / 20);

    for(int i = totalBars - 1; i >= InpForwardBars; i--) {

        DataRow row;

        // Donnees OHLCV
        row.time = timeArray[i];
        row.open = openArray[i];
        row.high = highArray[i];
        row.low = lowArray[i];
        row.close = closeArray[i];
        row.volume = (double)volumeArray[i];

        // Calculer indicateurs H1
        if(!CalculateIndicatorsH1(i, row)) {
            continue;
        }

        // Calculer indicateurs H4
        if(!CalculateIndicatorsH4(timeArray[i], row)) {
            continue;
        }

        // Calculer signaux (Poseidon)
        CalculateSignals(row);

        // Calculer filtres
        CalculateFilters(row);

        // Features temporelles
        CalculateTimeFeatures(row.time, row);

        // Target ML
        if(InpIncludeTarget) {
            SimulateTradeV2(i, row, closeArray, highArray, lowArray);
        } else {
            row.target_binary = -1;
            row.target_pct_change = 0.0;
            row.sl_price = 0.0;
            row.tp_price = 0.0;
        }

        // Ecrire dans CSV
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

    PrintFormat("=== EXPORT TERMINE: %d lignes exportees ===", exportedCount);
    PrintFormat("Fichier: MQL5/Files/Common/%s", fileName);
    Print("");
    Print("PROCHAINE ETAPE: Lancer script Python pour ajouter DXY/VIX/US10Y depuis Yahoo Finance");
}

//======================== INITIALISATION INDICATEURS ========================
bool InitIndicators()
{
    // Indicateurs H1 (Poseidon)
    hEMA21 = iMA(sym, InpTF, 21, 0, MODE_EMA, PRICE_CLOSE);
    hEMA55 = iMA(sym, InpTF, 55, 0, MODE_EMA, PRICE_CLOSE);

    hSMAfast = iMA(sym, InpTF, InpMACD_Fast, 0, MODE_SMA, PRICE_CLOSE);
    hSMAslow = iMA(sym, InpTF, InpMACD_Slow, 0, MODE_SMA, PRICE_CLOSE);

    hSMMA50_H1 = iMA(sym, InpTF, 50, 0, MODE_SMMA, PRICE_CLOSE);
    hSMMA200_H1 = iMA(sym, InpTF, 200, 0, MODE_SMMA, PRICE_CLOSE);

    // NOUVEAUX: ATR et ADX H1
    hATR14 = iATR(sym, InpTF, 14);
    hADX14 = iADX(sym, InpTF, 14);

    // NOUVEAUX: Indicateurs H4 (Poseidon)
    hSMMA50_H4 = iMA(sym, PERIOD_H4, 50, 0, MODE_SMMA, PRICE_CLOSE);
    hRSI_H4 = iRSI(sym, PERIOD_H4, InpRSIPeriod, PRICE_CLOSE);

    // Verification handles
    if(hEMA21 == INVALID_HANDLE || hEMA55 == INVALID_HANDLE ||
       hSMAfast == INVALID_HANDLE || hSMAslow == INVALID_HANDLE ||
       hSMMA50_H1 == INVALID_HANDLE || hSMMA200_H1 == INVALID_HANDLE ||
       hATR14 == INVALID_HANDLE || hADX14 == INVALID_HANDLE ||
       hSMMA50_H4 == INVALID_HANDLE || hRSI_H4 == INVALID_HANDLE) {
        Print("ERREUR: Handle indicateur invalide");
        return false;
    }

    return true;
}

//======================== LIBERATION INDICATEURS ========================
void ReleaseIndicators()
{
    if(hEMA21 != INVALID_HANDLE) IndicatorRelease(hEMA21);
    if(hEMA55 != INVALID_HANDLE) IndicatorRelease(hEMA55);
    if(hSMAfast != INVALID_HANDLE) IndicatorRelease(hSMAfast);
    if(hSMAslow != INVALID_HANDLE) IndicatorRelease(hSMAslow);
    if(hSMMA50_H1 != INVALID_HANDLE) IndicatorRelease(hSMMA50_H1);
    if(hSMMA200_H1 != INVALID_HANDLE) IndicatorRelease(hSMMA200_H1);
    if(hATR14 != INVALID_HANDLE) IndicatorRelease(hATR14);
    if(hADX14 != INVALID_HANDLE) IndicatorRelease(hADX14);
    if(hSMMA50_H4 != INVALID_HANDLE) IndicatorRelease(hSMMA50_H4);
    if(hRSI_H4 != INVALID_HANDLE) IndicatorRelease(hRSI_H4);
}

//======================== CALCUL INDICATEURS H1 ========================
bool CalculateIndicatorsH1(int shift, DataRow &row)
{
    double buffer[];
    ArraySetAsSeries(buffer, true);

    // EMA21
    if(CopyBuffer(hEMA21, 0, shift, 1, buffer) < 1) return false;
    row.ema21 = buffer[0];

    // EMA55
    if(CopyBuffer(hEMA55, 0, shift, 1, buffer) < 1) return false;
    row.ema55 = buffer[0];

    // MACD custom (Poseidon)
    if(!CalculateMACD_SMA(shift, row.macd, row.macd_signal, row.macd_hist)) return false;

    // SMMA50
    if(CopyBuffer(hSMMA50_H1, 0, shift, 1, buffer) < 1) return false;
    row.smma50 = buffer[0];

    // SMMA200
    if(CopyBuffer(hSMMA200_H1, 0, shift, 1, buffer) < 1) return false;
    row.smma200 = buffer[0];

    // ATR14
    if(CopyBuffer(hATR14, 0, shift, 1, buffer) < 1) return false;
    row.atr14 = buffer[0];

    // ADX14
    if(CopyBuffer(hADX14, 0, shift, 1, buffer) < 1) return false;
    row.adx14 = buffer[0];

    if(CopyBuffer(hADX14, 1, shift, 1, buffer) < 1) return false;
    row.di_plus = buffer[0];

    if(CopyBuffer(hADX14, 2, shift, 1, buffer) < 1) return false;
    row.di_minus = buffer[0];

    return true;
}

//======================== CALCUL INDICATEURS H4 ========================
bool CalculateIndicatorsH4(datetime barTime, DataRow &row)
{
    double buffer[];
    ArraySetAsSeries(buffer, true);

    // Trouver la barre H4 correspondante
    int h4_shift = iBarShift(sym, PERIOD_H4, barTime);
    if(h4_shift < 0) return false;

    // SMMA50 H4
    if(CopyBuffer(hSMMA50_H4, 0, h4_shift, 1, buffer) < 1) return false;
    row.smma50_h4 = buffer[0];

    // RSI H4 (periode 12, overbought 80)
    if(CopyBuffer(hRSI_H4, 0, h4_shift, 1, buffer) < 1) return false;
    row.rsi_h4 = buffer[0];

    // Tendance H4 (price vs SMMA50 H4)
    if(row.close > row.smma50_h4 * 1.001) {
        row.trend_h4 = 1;  // Haussiere
    } else if(row.close < row.smma50_h4 * 0.999) {
        row.trend_h4 = -1; // Baissiere
    } else {
        row.trend_h4 = 0;  // Neutre
    }

    return true;
}

//======================== MACD CUSTOM SMA (Poseidon) ========================
bool CalculateMACD_SMA(int shift, double &macd, double &signal, double &hist)
{
    int need = MathMax(InpMACD_Slow, InpMACD_Signal) + 5;
    double fast[], slow[];
    ArraySetAsSeries(fast, true);
    ArraySetAsSeries(slow, true);

    if(CopyBuffer(hSMAfast, 0, shift, need, fast) < need) return false;
    if(CopyBuffer(hSMAslow, 0, shift, need, slow) < need) return false;

    double macdArr[];
    ArrayResize(macdArr, need);
    for(int i = 0; i < need; i++) {
        macdArr[i] = fast[i] - slow[i];
    }

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

//======================== CALCUL SIGNAUX (Poseidon) ========================
void CalculateSignals(DataRow &row)
{
    // Signal EMA (Poseidon)
    if(row.ema21 > row.ema55) row.signal_ema = 1;
    else if(row.ema21 < row.ema55) row.signal_ema = -1;
    else row.signal_ema = 0;

    // Signal MACD (Poseidon)
    if(row.macd_hist > 0) row.signal_macd = 1;
    else if(row.macd_hist < 0) row.signal_macd = -1;
    else row.signal_macd = 0;

    // Signal SMMA (Poseidon)
    if(row.close > row.smma50) row.signal_smma = 1;
    else if(row.close < row.smma50) row.signal_smma = -1;
    else row.signal_smma = 0;

    // Score total (Poseidon: minimum 2/3 signaux)
    row.signal_score = row.signal_ema + row.signal_macd + row.signal_smma;
}

//======================== CALCUL FILTRES ========================
void CalculateFilters(DataRow &row)
{
    // Filtre RSI H4 (periode 12, overbought 80, oversold 25)
    if(row.rsi_h4 >= InpRSIOverbought) {
        row.rsi_filter = 1;  // Overbought - bloquer SELL
    } else if(row.rsi_h4 <= InpRSIOversold) {
        row.rsi_filter = -1; // Oversold - bloquer BUY
    } else {
        row.rsi_filter = 0;  // OK
    }

    // Filtre ADX (market regime)
    if(row.adx14 < 20) {
        row.adx_regime = 0;        // Range
    } else if(row.adx14 < 40) {
        row.adx_regime = 1;        // Tendance
    } else {
        row.adx_regime = 2;        // Forte tendance
    }
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
    row.in_session = (dt.hour >= 6 && dt.hour < 15) ? 1 : 0;
}

//======================== SIMULATION TRADE (TP/SL ATR) ========================
void SimulateTradeV2(int shift, DataRow &row,
                     const double &closeArr[], const double &highArr[], const double &lowArr[])
{
    // Seulement si signal fort (score >= 2 ou <= -2) - comme Poseidon
    if(row.signal_score < 2 && row.signal_score > -2) {
        row.target_binary = -1;
        row.target_pct_change = 0.0;
        row.sl_price = 0.0;
        row.tp_price = 0.0;
        return;
    }

    int direction = (row.signal_score >= 2) ? 1 : -1;
    double entry = row.close;

    // TP/SL dynamiques bases sur ATR14
    double atr = row.atr14;
    double sl_distance = atr * InpSL_ATR_Multiplier;
    double tp_distance = atr * InpTP_ATR_Multiplier;

    double sl, tp;
    if(direction > 0) {
        sl = entry - sl_distance;
        tp = entry + tp_distance;
    } else {
        sl = entry + sl_distance;
        tp = entry - tp_distance;
    }

    row.sl_price = sl;
    row.tp_price = tp;

    // Break Even (Poseidon)
    double be_level_buy = entry + sl_distance;
    double be_level_sell = entry - sl_distance;
    bool be_activated = false;

    // Simuler les barres suivantes
    for(int i = shift - 1; i >= MathMax(0, shift - InpForwardBars); i--) {
        double h = highArr[i];
        double l = lowArr[i];

        if(direction > 0) {
            // BUY
            if(InpUseBreakEven && !be_activated && h >= be_level_buy) {
                sl = entry;
                be_activated = true;
            }

            if(l <= sl) {
                row.target_binary = be_activated ? 1 : 0;
                row.target_pct_change = be_activated ? 0.0 : (-100.0 * sl_distance / entry);
                return;
            }

            if(h >= tp) {
                row.target_binary = 1;
                row.target_pct_change = 100.0 * tp_distance / entry;
                return;
            }
        } else {
            // SELL
            if(InpUseBreakEven && !be_activated && l <= be_level_sell) {
                sl = entry;
                be_activated = true;
            }

            if(h >= sl) {
                row.target_binary = be_activated ? 1 : 0;
                row.target_pct_change = be_activated ? 0.0 : (-100.0 * sl_distance / entry);
                return;
            }

            if(l <= tp) {
                row.target_binary = 1;
                row.target_pct_change = 100.0 * tp_distance / entry;
                return;
            }
        }
    }

    // Ni TP ni SL touche
    row.target_binary = -1;

    int future_idx = MathMax(0, shift - InpFutureBars);
    if(future_idx >= 0 && future_idx < ArraySize(closeArr)) {
        double future_close = closeArr[future_idx];
        row.target_pct_change = 100.0 * (future_close - entry) / entry;
    } else {
        row.target_pct_change = 0.0;
    }
}

//======================== ECRITURE CSV ========================
void WriteCSVHeader(int handle)
{
    string header = "time,open,high,low,close,volume,";
    header += "ema21,ema55,macd,macd_signal,macd_hist,smma50,smma200,";
    header += "atr14,adx14,di_plus,di_minus,";
    header += "smma50_h4,rsi_h4,trend_h4,";
    header += "signal_ema,signal_macd,signal_smma,signal_score,";
    header += "rsi_filter,adx_regime,";
    header += "hour,day_of_week,month,year,in_session,";
    header += "target_binary,target_pct_change,sl_price,tp_price";

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

    line += DoubleToString(row.atr14, dig) + ",";
    line += DoubleToString(row.adx14, 2) + ",";
    line += DoubleToString(row.di_plus, 2) + ",";
    line += DoubleToString(row.di_minus, 2) + ",";

    line += DoubleToString(row.smma50_h4, dig) + ",";
    line += DoubleToString(row.rsi_h4, 2) + ",";
    line += IntegerToString(row.trend_h4) + ",";

    line += IntegerToString(row.signal_ema) + ",";
    line += IntegerToString(row.signal_macd) + ",";
    line += IntegerToString(row.signal_smma) + ",";
    line += IntegerToString(row.signal_score) + ",";

    line += IntegerToString(row.rsi_filter) + ",";
    line += IntegerToString(row.adx_regime) + ",";

    line += IntegerToString(row.hour) + ",";
    line += IntegerToString(row.day_of_week) + ",";
    line += IntegerToString(row.month) + ",";
    line += IntegerToString(row.year) + ",";
    line += IntegerToString(row.in_session) + ",";

    line += IntegerToString(row.target_binary) + ",";
    line += DoubleToString(row.target_pct_change, 4) + ",";
    line += DoubleToString(row.sl_price, dig) + ",";
    line += DoubleToString(row.tp_price, dig);

    FileWrite(handle, line);
}
//+------------------------------------------------------------------+
