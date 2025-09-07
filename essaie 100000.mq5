//+------------------------------------------------------------------+
//|                                   Poseidon_London_1H_fixedRisk   |
//|  H1 – Entrées 7:00-14:00 (serveur)                               |
//|  Signal: EMA21/55 OU MACD(SMA 20,45,15)                          |
//|  Max 2 trades/jour, SL 0.25%, TP +500$                           |
//|  BE (0$) dès profit >= 300$ OU move >= 3R                        |
//|  Risque FIXE = InpRiskPercent (pas de palier / pas de séries)    |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

CTrade Trade;

//======================== Inputs utilisateur ========================
input long     InpMagic                = 20250811;
input bool     InpAllowBuys            = true;
input bool     InpAllowSells           = true;

// --- Export CSV Inputs ---
input bool     InpAutoExportOnDeinit   = false;        // Export automatique à la fermeture de l'EA
input datetime InpExportStartDate      = D'2000.01.01'; // Date début export
input datetime InpExportEndDate        = D'2045.01.01'; // Date fin export
input string   InpFileSuffix           = "POSEIDON";    // Suffixe du fichier CSV

// --- Choix des signaux ---
enum SignalMode { EMA_OR_MACD=0, EMA_ONLY=1, MACD_ONLY=2 };
input SignalMode InpSignalMode         = EMA_OR_MACD; // "OU" par défaut
input bool     InpUseEMA_Cross         = true;        // EMA21/55 croisement
input bool     InpUseMACD              = true;        // MACD SMA 20/45/15

// --- MACD SMA config ---
input int      InpMACD_Fast            = 20;          // SMA rapide
input int      InpMACD_Slow            = 45;          // SMA lente
input int      InpMACD_Signal          = 15;          // SMA du MACD

// --- Risque / gestion (en %) ---
input double InpRiskPercent        = 1.0;   // % de la BALANCE risqué par trade
// [ADDED] Poseidon 03/09/2025 Option A – réduction du risque après série de pertes
input bool   UseLossStreakReduction = true;   // ON/OFF
input int    LossStreakTrigger      = 7;      // Value=7 / Start=3 / Step=1 / Stop=15
input double LossStreakFactor       = 0.50;   // Value=0.50 / Start=0.20 / Step=0.10 / Stop=1.00

// [ADDED] Poseidon 03/09/2025 Option A – RISQUE EN MONTANT FIXE (devise du compte)
input bool   UseFixedRiskMoney = true;   // Utiliser un montant fixe (€) au lieu du %
input double FixedRiskMoney     = 100.0; // Montant risqué par trade (ex: 100€)
input double ReducedRiskMoney   = 50.0;  // Montant risqué sous série de pertes (ex: 50€)

input double InpSL_PercentOfPrice  = 0.25;  // SL = % du prix d'entrée (ex: 0.25 => 0.25%)
input double InpTP_PercentOfPrice  = 1.25;  // TP = % du prix d'entrée
input double InpBE_TriggerPercent  = 0.70;  // Passer BE quand le prix a évolué de +0.70% depuis l'entrée
input int    InpMaxTradesPerDay    = 2;

// --- Fenêtre d'ouverture ---
input ENUM_TIMEFRAMES InpSignalTF      = PERIOD_H1;   // TF signaux (H1)
input int      InpSessionStartHour     = 7;           // Ouverture 7h (heure serveur)
input int      InpSessionEndHour       = 14;          // Fermeture 14h (pas de nouvelles entrées après)
input int      InpSlippagePoints       = 20;
input bool     InpVerboseLogs          = false;
// [ADDED] === SMMA50 + Score conditions (optimisables) ===
input bool InpUseSMMA50Trend    = true;             // Filtre tendance SMMA50
input int  InpSMMA_Period       = 50;               // Période SMMA (Value=50 / Start=20 / Step=5 / Stop=200)
input ENUM_TIMEFRAMES InpSMMA_TF = PERIOD_H4;       // UT SMMA (H4)
input int  InpMinConditions     = 3;                // Conditions minimales requises (Value=3 / Start=2 / Step=1 / Stop=4)

//=== Month Filter Inputs START ===========================================
input bool InpTrade_Janvier   = false;  // Trader en Janvier
input bool InpTrade_Fevrier   = false;  // Trader en Fevrier
input bool InpTrade_Mars      = false;  // Trader en Mars
input bool InpTrade_Avril     = true;   // Trader en Avril
input bool InpTrade_Mai       = true;   // Trader en Mai
input bool InpTrade_Juin      = true;   // Trader en Juin
input bool InpTrade_Juillet   = true;   // Trader en Juillet
input bool InpTrade_Aout      = true;   // Trader en Aout
input bool InpTrade_Septembre = true;   // Trader en Septembre
input bool InpTrade_Octobre   = true;   // Trader en Octobre
input bool InpTrade_Novembre  = true;   // Trader en Novembre
input bool InpTrade_Decembre  = true;   // Trader en Decembre
//=== Month Filter Inputs END =============================================

//======================== Variables ========================
datetime lastBarTime=0;
string   sym; int dig; double pt;
int tradedDay=-1, tradesCountToday=0;
int gLossStreak = 0;   // [ADDED] Compteur pertes consécutives – Poseidon 03/09/2025 Option A

// Handles EMA/MAs pour MACD SMA
int hEMA21=-1, hEMA55=-1;
int hSMAfast=-1, hSMAslow=-1;

int hSMMA50 = -1;   // [ADDED] Handle SMMA50

//======================== CSV Export Function ========================
void ExportTradeHistory(){
   string symbol = _Symbol;
   string csv_data;
   
   string file_name = StringSubstr(symbol, 0, 6) + "_" + InpFileSuffix + ".csv";
    int file_handle = FileOpen(file_name, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, 0, CP_UTF8);
 if(file_handle == INVALID_HANDLE)
 {
 Print("ERROR: Failed to create CSV file: ", file_name, " Error: ", GetLastError());
  return;
   }
     Print("CSV file opened successfully: ", file_name);
   if(HistorySelect(InpExportStartDate, InpExportEndDate)){
      
      csv_data = "magic,symbol,type,time_open,time_close,price_open,price_close,stop_loss,take_profit,volume,position_pnl,position_pnl_pips,swap,swap_pips,commission,commission_pips,total_pnl,total_pnl_pips,position_id,comment";
      FileWrite(file_handle, csv_data);

      ulong deal_in_ticket = -1;
      int deals_total = HistoryDealsTotal();
      ulong positions[];
      ArrayResize(positions, deals_total, true);
      int position_cnt = 0;
      int size = 0;

      for(int i = 0; i < deals_total; i++){
         deal_in_ticket = HistoryDealGetTicket(i);
         if(deal_in_ticket > 0 && HistoryDealGetInteger(deal_in_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN){
            ulong position_id = HistoryDealGetInteger(deal_in_ticket, DEAL_POSITION_ID);
            
            if(HistoryDealGetInteger(deal_in_ticket, DEAL_TYPE) > 1) continue;
            
            bool is_dupe = false;
            
            for(int j = 0; j < size; j++){
               if(positions[j] == position_id){
                  is_dupe = true;
                  break;
               }
            }
            if(!is_dupe){
               positions[size++] = position_id;
            }
         }
      }

      int cnt = 0;
      for(int i = 0; i < size; i++){
         ulong position_id = positions[i];
         long magic_number = -1, direction = -1, close_time = -1, open_time = -1;
         double open_price = -1, close_price = -1, deal_volume = 0;
         double take_profit = -1, stop_loss = -1, profit = 0, swap = 0, commission = 0;
         string comment = "";

         if(HistorySelectByPosition(position_id)){
            cnt++;
            int _history_deals_by_pos = HistoryDealsTotal();

            for(int j = 0; j < _history_deals_by_pos; j++){
               ulong deal_ticket = HistoryDealGetTicket(j);
               
               if(deal_ticket == 0) continue;
                
               if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT){
                  close_time = HistoryDealGetInteger(deal_ticket, DEAL_TIME);
                  close_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                  deal_volume += HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
               }
               if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN){
                  direction = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
                  open_time = HistoryDealGetInteger(deal_ticket, DEAL_TIME);
                  open_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                  stop_loss = HistoryDealGetDouble(deal_ticket, DEAL_SL);
                  take_profit = HistoryDealGetDouble(deal_ticket, DEAL_TP);
               }
               magic_number = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
               symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
               commission += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
               swap += HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
               profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
               comment += HistoryDealGetString(deal_ticket, DEAL_COMMENT) + "/";
            }

            double tick_value_profit = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
            double tick_value_loss = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
            double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
            double points = SymbolInfoDouble(symbol, SYMBOL_POINT);
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

            double total_profit = profit + swap + commission;
            double tick_value = (profit < 0) ? tick_value_loss : tick_value_profit;

            csv_data = IntegerToString(magic_number) + ",";
            csv_data += symbol + ",";
            csv_data += IntegerToString(int(direction)) + ",";
            csv_data += IntegerToString(open_time) + ",";
            csv_data += IntegerToString(close_time) + ",";
            csv_data += DoubleToString(open_price, digits) + ",";
            csv_data += DoubleToString(close_price, digits) + ",";
            csv_data += DoubleToString(stop_loss, digits) + ",";
            csv_data += DoubleToString(take_profit, digits) + ",";
            csv_data += DoubleToString(deal_volume, 2) + ",";
            csv_data += DoubleToString(profit, 2) + ",";
            csv_data += DoubleToString(profit / (deal_volume / tick_size * tick_value) / points / 10, 2) + ",";
            csv_data += DoubleToString(swap, 2) + ",";
            csv_data += DoubleToString(swap / (deal_volume / tick_size * tick_value) / points / 10, 2) + ",";
            csv_data += DoubleToString(commission, 2) + ",";
            csv_data += DoubleToString(commission / (deal_volume / tick_size * tick_value) / points / 10, 2) + ",";
            csv_data += DoubleToString(total_profit, 2) + ",";
            csv_data += DoubleToString(total_profit / (deal_volume / tick_size * tick_value) / points / 10, 2) + ",";
            csv_data += IntegerToString(position_id) + ",";
            csv_data += comment;

            FileWrite(file_handle, csv_data);
         }
      }
      printf("%d positions exportées vers %s", cnt, file_name);
   }
   
   FileFlush(file_handle);
   FileClose(file_handle);
   Print("CSV export completed. File saved to Common folder: ", file_name);
}
//======================== Tester Export Handler ========================
   void OnTesterDeinit()
 {
   if(InpAutoExportOnDeinit)
 {
  Print("Starting CSV export from Strategy Tester...");
   ExportTradeHistory();
   Print("CSV export completed");
 }

//======================== Utils Temps ======================
bool IsNewBar(){ datetime ct=iTime(sym, InpSignalTF, 0); if(ct!=lastBarTime){lastBarTime=ct; return true;} return false; }

void ResetDayIfNeeded(){ MqlDateTime t; TimeToStruct(TimeCurrent(), t); if(tradedDay!=t.day_of_year){ tradedDay=t.day_of_year; tradesCountToday=0; } }
bool CanOpenToday(){ ResetDayIfNeeded(); return tradesCountToday<InpMaxTradesPerDay; }
void MarkTradeOpened(){ ResetDayIfNeeded(); tradesCountToday++; }

bool InEntryWindow()
{
   MqlDateTime t; TimeToStruct(TimeCurrent(), t);
   if(InpSessionStartHour<=InpSessionEndHour)
      return (t.hour>=InpSessionStartHour && t.hour<InpSessionEndHour);
   return (t.hour>=InpSessionStartHour || t.hour<InpSessionEndHour);
}

//======================== Indicateurs ======================
bool GetEMAs(double &e21_1,double &e55_1,double &e21_2,double &e55_2)
{
   double b21[],b55[]; ArraySetAsSeries(b21,true); ArraySetAsSeries(b55,true);
   if(CopyBuffer(hEMA21,0,1,2,b21)<2) return false;
   if(CopyBuffer(hEMA55,0,1,2,b55)<2) return false;
   e21_1=b21[0]; e21_2=b21[1]; e55_1=b55[0]; e55_2=b55[1];
   return true;
}

// Calcule MACD SMA(20,45) et son Signal SMA(15) via SMA on-price + SMA sur MACD
bool GetMACD_SMA(double &macd_1,double &sig_1,double &macd_2,double &sig_2)
{
   int need = MathMax(MathMax(InpMACD_Fast, InpMACD_Slow), InpMACD_Signal) + 5;
   double fast[], slow[];
   ArraySetAsSeries(fast,true); ArraySetAsSeries(slow,true);
   if(CopyBuffer(hSMAfast,0,1,need,fast) < need) return false;
   if(CopyBuffer(hSMAslow,0,1,need,slow) < need) return false;

   double macdArr[]; ArrayResize(macdArr, need);
   for(int i=0;i<need;i++) macdArr[i] = fast[i] - slow[i];

   double sigArr[]; ArrayResize(sigArr, need);
   int p = InpMACD_Signal;
   double acc=0;
   for(int i=0;i<need;i++)
   {
      acc += macdArr[i];
      if(i>=p) acc -= macdArr[i-p];
      if(i>=p-1) sigArr[i] = acc / p; else sigArr[i] = macdArr[i];
   }

   macd_1 = macdArr[0];
   sig_1  = sigArr[0];
   macd_2 = macdArr[1];
   sig_2  = sigArr[1];
   return true;
}

//------------------------ Signaux ----------------------
void ComputeSignals(bool &buySig,bool &sellSig)
{
   buySig=false; sellSig=false;

   bool emaBuy=false, emaSell=false;
   if(InpUseEMA_Cross && (InpSignalMode==EMA_ONLY || InpSignalMode==EMA_OR_MACD))
   {
      double e21_1,e55_1,e21_2,e55_2;
      if(GetEMAs(e21_1,e55_1,e21_2,e55_2))
      {
         emaBuy  = (e21_2<=e55_2 && e21_1>e55_1);
         emaSell = (e21_2>=e55_2 && e21_1<e55_1);
      }
   }

   bool macdBuy=false, macdSell=false;
   if(InpUseMACD && (InpSignalMode==MACD_ONLY || InpSignalMode==EMA_OR_MACD))
   {
      double m1,s1,m2,s2;
      if(GetMACD_SMA(m1,s1,m2,s2))
      {
         macdBuy  = (m2<=s2 && m1>s1);   // croisement haussier
         macdSell = (m2>=s2 && m1<s1);   // croisement baissier
      }
   }

   if(InpSignalMode==EMA_ONLY)      { buySig=emaBuy;  sellSig=emaSell; }
   else if(InpSignalMode==MACD_ONLY){ buySig=macdBuy; sellSig=macdSell; }
   else /* EMA_OR_MACD */           {
      buySig  = (emaBuy  || macdBuy);
      sellSig = (emaSell || macdSell);
   }
}
// [ADDED] ---- Helpers SMMA/EMA/MACD pour scoring 4 conditions ----

bool GetSMMA50(double &out_smma)
{
   if(!InpUseSMMA50Trend) return false;
   if(hSMMA50==INVALID_HANDLE) return false;
   double b[]; ArraySetAsSeries(b,true);
   if(CopyBuffer(hSMMA50,0,0,1,b)<1) return false;
   out_smma = b[0];
   return true;
}

// +1 (buy) / -1 (sell) / 0 neutre
int TrendDir_SMMA50()
{
   if(!InpUseSMMA50Trend) return 0;
   double smma=0.0; if(!GetSMMA50(smma)) return 0;
   double bid=SymbolInfoDouble(sym,SYMBOL_BID), ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   double px=(bid+ask)*0.5;
   if(px>smma) return +1;
   if(px<smma) return -1;
   return 0;
}

// EMA21/55 (croisement)
bool GetEMACrossSignal(bool &buy,bool &sell)
{
   buy=false; sell=false;
   double e21_1,e55_1,e21_2,e55_2;
   if(!GetEMAs(e21_1,e55_1,e21_2,e55_2)) return false;
   buy  = (e21_2<=e55_2 && e21_1>e55_1);
   sell = (e21_2>=e55_2 && e21_1<e55_1);
   return true;
}

// MACD (SMA-based existant) – croisement des lignes
bool GetMACD_CrossSignal(bool &buy,bool &sell)
{
   buy=false; sell=false;
   double m1,s1,m2,s2;
   if(!GetMACD_SMA(m1,s1,m2,s2)) return false;
   buy  = (m2<=s2 && m1>s1);
   sell = (m2>=s2 && m1<s1);
   return true;
}

// MACD – histogramme (MAIN - SIGNAL)
bool GetMACD_HistSignal(bool &buy,bool &sell)
{
   buy=false; sell=false;
   double m1,s1,m2,s2;
   if(!GetMACD_SMA(m1,s1,m2,s2)) return false;
   double hist = (m1 - s1);
   buy  = (hist > 0.0);
   sell = (hist < 0.0);
   return true;
}

//======================== Prix/SL/TP ========================
void MakeSL_Init(int dir,double entry,double &sl)
{
   double p=InpSL_PercentOfPrice/100.0;
   if(dir>0) sl=entry*(1.0-p); else sl=entry*(1.0+p);
   sl=NormalizeDouble(sl,dig);
}

bool PriceForTargetProfit(int dir,double lots,double entry,double targetUSD,double &priceOut)
{
   // Recherche binaire +/- 3% autour de l'entrée
   double range = entry*0.03;
   double lo = (dir>0? entry : entry-range), hi=(dir>0? entry+range : entry);
   for(int i=0;i<50;i++){
      double mid=(lo+hi)*0.5;
      double pf=0.0; bool ok = (dir>0)? OrderCalcProfit(ORDER_TYPE_BUY,sym,lots,entry,mid,pf)
                                      : OrderCalcProfit(ORDER_TYPE_SELL,sym,lots,entry,mid,pf);
      if(!ok) return false;
      if(pf<targetUSD){ if(dir>0) lo=mid; else hi=mid; }
      else             { if(dir>0) hi=mid; else lo=mid; }
   }
   priceOut=NormalizeDouble((lo+hi)*0.5,dig);
   return true;
}

//======================== Sizing 1% FIXE ===================
double LossPerLotAtSL(int dir,double entry,double sl)
{
   double p=0.0; bool ok = (dir>0)? OrderCalcProfit(ORDER_TYPE_BUY,sym,1.0,entry,sl,p)
                                  : OrderCalcProfit(ORDER_TYPE_SELL,sym,1.0,entry,sl,p);
   if(ok) return MathAbs(p);
   double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double dist=MathAbs(entry-sl);
   if(tv>0 && ts>0) return (dist/ts)*tv;
   return 0.0;
}

double LotsFromRisk(int dir,double entry,double sl)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
// [CHANGED] Poseidon 03/09/2025 Option A – risque en € fixe + réduction série
double riskMoney = equity*(InpRiskPercent/100.0); // fallback %
if(UseFixedRiskMoney)
   riskMoney = FixedRiskMoney;

if(UseLossStreakReduction)
{
   gLossStreak = CountConsecutiveLosses();
   if(gLossStreak >= LossStreakTrigger)
   {
      if(UseFixedRiskMoney) riskMoney = ReducedRiskMoney;
      else                  riskMoney *= LossStreakFactor;
   }
   if(InpVerboseLogs) PrintFormat("[LossStreak] count=%d, riskMoney=%.2f", gLossStreak, riskMoney);
}

double risk=riskMoney;
   double lossPerLot=LossPerLotAtSL(dir,entry,sl);
   if(lossPerLot<=0) return 0.0;
   double lots=risk/lossPerLot;
   double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   double minL=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxL=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   if(step<=0) step=0.01;
   lots=MathFloor(lots/step)*step;
   lots=MathMax(minL,MathMin(lots,maxL));
   if(InpVerboseLogs) PrintFormat("[Sizing FIX] equity=%.2f risk$=%.2f entry=%.2f sl=%.2f lossPerLot=%.2f lots=%.2f",
                                  equity, risk, entry, sl, lossPerLot, lots);
   return lots;
}

//======================== Ouverture ========================
void TryOpenTrade()
{
   if(!InEntryWindow()) return;
   if(!CanOpenToday()) return;

   // [CHANGED] Scoring 4 conditions (SMMA + EMA + MACD_hist + MACD_cross) + filtre SMMA directionnel
int scoreBuy=0, scoreSell=0;

// 1) SMMA50 H4 tendance
int tdir = TrendDir_SMMA50(); // +1/-1/0
if(InpUseSMMA50Trend){
   if(tdir>0) scoreBuy++;
   else if(tdir<0) scoreSell++;
   else return; // neutre -> pas d'entrée
}

// 2) EMA21/55 cross
bool emaB=false, emaS=false; GetEMACrossSignal(emaB, emaS);
if(emaB) scoreBuy++; if(emaS) scoreSell++;

// 3) MACD histogramme
bool mhB=false, mhS=false; GetMACD_HistSignal(mhB, mhS);
if(mhB) scoreBuy++; if(mhS) scoreSell++;

// 4) MACD croisement lignes
bool mcB=false, mcS=false; GetMACD_CrossSignal(mcB, mcS);
if(mcB) scoreBuy++; if(mcS) scoreSell++;

bool allowBuy  = (!InpUseSMMA50Trend || tdir>0);
bool allowSell = (!InpUseSMMA50Trend || tdir<0);

int dir=0;
if(scoreBuy  >= InpMinConditions && allowBuy  && InpAllowBuys)  dir=+1;
if(scoreSell >= InpMinConditions && allowSell && InpAllowSells && dir==0) dir=-1;
if(dir==0) return;

   double entry=(dir>0)? SymbolInfoDouble(sym,SYMBOL_ASK):SymbolInfoDouble(sym,SYMBOL_BID);
   double sl; MakeSL_Init(dir,entry,sl);
   double lots=LotsFromRisk(dir,entry,sl);
   if(lots<=0) return;

   // TP en % du prix d'entrée
double tpPrice = (dir>0 ? entry*(1.0 + InpTP_PercentOfPrice/100.0)
                        : entry*(1.0 - InpTP_PercentOfPrice/100.0));

   Trade.SetExpertMagicNumber(InpMagic);
   Trade.SetDeviationInPoints(InpSlippagePoints);
   string cmt="BASE";
   if(UseLossStreakReduction && gLossStreak >= LossStreakTrigger) cmt="RISK-REDUCED";   // [ADDED]
   bool ok=(dir>0)? Trade.Buy(lots,sym,entry,sl,tpPrice,cmt)
                  : Trade.Sell(lots,sym,entry,sl,tpPrice,cmt);
   if(ok) MarkTradeOpened();
}

//======================== Gestion BE =======================
double RPrice(const double entry){ return entry*(InpSL_PercentOfPrice/100.0); } // 1R = SL% d'entrée

void ManageBreakEvenPercent(const string symbol_)   // nom changé pour ne pas masquer une globale
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;         // sélection
      if(PositionGetString(POSITION_SYMBOL)!=symbol_) continue;          // filtre symbole

      long   type  = (long)PositionGetInteger(POSITION_TYPE);            // BUY/SELL
      double entry = PositionGetDouble (POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble (POSITION_SL);
      double tp    = PositionGetDouble (POSITION_TP);
      double price = (type==POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(symbol_, SYMBOL_BID)
                     : SymbolInfoDouble(symbol_, SYMBOL_ASK);

      // Seuil BE : +0.70% depuis l'entrée OU 3R
      const double beTrigger = (type==POSITION_TYPE_BUY)
                               ? entry*(1.0 + InpBE_TriggerPercent/100
