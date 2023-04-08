//+------------------------------------------------------------------+
//|                                                   Leprechaun.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#define VERSION "1.16"
#property copyright "NAG"
#property link      "https://sites.google.com/site/hhosaka183"
#property version   VERSION
#property strict

#define MAX_STACK (64)
#define TRY_COUNT (20)
#define SLIP_PAGE (20)
#define MINIMUM_ORDER_SPAN (120)
#define RECOVER_SAMPLES (5)
#define STEP_RATE (1.5)
#define TP_SET_MARGIN (0.05)
#define REFRESH_PERIOD (60*60)
#define ID_OBJECT_SCHEDULE "schedule"
#define ID_OBJECT_MODE "mode"

//--- input parameters
enum MODE{ACTIVE, DEACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL, MODE_UNDEFINED};
enum TYPE{BUY=0, SELL=1, BOTH=2, TYPE_UNDEFINED=3};

input int magicNumberBuy=19640429;// Long側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotBuy=0.01;// Long側の初期ロット
input MODE initialModeBuy=ACTIVE;// Long側のモード

input int magicNumberSell=19671120;// Short側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotSell=0.01;// Short側の初期ロット
input MODE initialModeSell=ACTIVE;// Short側のモード

input int alertStack=10;// 警戒段数。ブレークイーブンでクローズします
input double recoverThresholdOnAlert=0.9;//警戒モード時のポジション取得閾値
input int maxStack=MAX_STACK;// 論理最大段数。64以下。
input double maxLot=129;// 許容する最大ロット倍率
input double pipsStepSize=100;//1ステップのサイズの0.1Pips単位
input double rateProfit=0.4;//利確の割合

input int timelag=7;//時差(時間)
input color colorText=clrYellow;//文字色

static double TOTAL_LOTS[MAX_STACK];
static int countSchedule;
static TYPE typeSchedule;
static MODE modeSchedule;
static datetime datetimeSchedule;
static datetime timeAdjust=0;
static MODE modes[2];

#include <stdlib.mqh> 

//+------------------------------------------------------------------+
//| Framework Function                                               |
//+------------------------------------------------------------------+

int OnInit(){
//Fail safe
//   if(!IsDemo())
//      return INIT_FAILED;

   Print("version=",VERSION);

   if(maxStack>MAX_STACK)
      return INIT_FAILED;

   if(modes[0]==MODE_UNDEFINED || modes[1]==MODE_UNDEFINED)
      return INIT_FAILED;

   InitialStatics();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   DestroyLabels();
}

void OnTick(){
   if(IsExpertEnabled()){
      bool forceUpdate=CheckSchedule();

      Tick(OP_BUY, modes[BUY], magicNumberBuy, NormalizeDouble(initialLotBuy , Digits()), forceUpdate);
      Tick(OP_SELL, modes[SELL], magicNumberSell, NormalizeDouble(initialLotSell , Digits()), forceUpdate);
   }
}

//+------------------------------------------------------------------+
//| Display Function                                                 |
//+------------------------------------------------------------------+

void CreateLabel(string id, int x, int y){
   ObjectCreate(id, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, id, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, id, OBJPROP_YDISTANCE, y);
}

void SetLabel(string id, string buf){
   ObjectSetText(id, buf, 12, "Meiryo", colorText);
}

void DisplayLabels(){
   DisplayMode();
   DisplaySchedule();
}

void DestroyLabels(){
   ObjectDelete(ID_OBJECT_MODE);
   ObjectDelete(ID_OBJECT_SCHEDULE);
}

void DisplayMode(){
   SetLabel(ID_OBJECT_MODE,
      "CURRENT=>BUY:"+EnumToString(modes[BUY])
      +" /SELL:"+EnumToString(modes[SELL]));
}

void DisplaySchedule(){
   SetLabel(ID_OBJECT_SCHEDULE,
      "WILL BE =>"+(
      countSchedule==0?
      "No Schedule":
      EnumToString(typeSchedule)+":"
      +EnumToString(modeSchedule)
      +"("+TimeToStr(datetimeSchedule)+")"
      +"["+IntegerToString(countSchedule)+"]"));
}

//+------------------------------------------------------------------+
//| Utility Function                                                 |
//+------------------------------------------------------------------+

void InitialStatics(){
   TOTAL_LOTS[0]=0;
   for(int i=1; i<MAX_STACK; ++i){
      TOTAL_LOTS[i]=TOTAL_LOTS[i-1]+GetLotRate(i-1);
   }
   ReadSchedule();
   timeAdjust=0;
   modes[BUY]=initialModeBuy;
   modes[SELL]=initialModeSell;

   CreateLabel(ID_OBJECT_MODE, 0, 20);
   CreateLabel(ID_OBJECT_SCHEDULE, 0, 40);
   DisplayLabels();
}

bool PrintError(string func, int line){
   static int prevError=0;
   
   int error = GetLastError();
   if(error!=0 && error!=prevError){
      prevError=error;
      string buf = "ERROR:" + func + "(" + IntegerToString(line) + ")=" + ErrorDescription(error);
      Print(buf);
      if(!IsTesting()){
         SendMail("Found some error","Hi Boss. \r\nIt's your Leprechaun on "+IntegerToString(AccountNumber())+".\r\n I have found some error\"" + buf + "\" on my task. Let you check it.");
      }
   }
   return false;
}

//
// チケット指定のOrderSelectが失敗することは考えにくいので返り値の確認を省略する。
//
void OrderSelectByTicket(int ticket, string func, int line){
   if(!OrderSelect(ticket, SELECT_BY_TICKET)){
      PrintError(func, line);
   }
}

bool CollectTickets(int magicNumber, int& tickets[], int&count){
   count = 0;
   int total = OrdersTotal();

   for (int i=0 ; i<total; ++i) {
      if(OrderSelect(i, SELECT_BY_POS)){
         if (OrderMagicNumber()==magicNumber
               && OrderSymbol()==Symbol()){
            tickets[count++]=OrderTicket();
         }
      }
      else{
         return PrintError(__FUNCTION__,__LINE__);
      }
   }
   return true;
}

double GetStepSize(){
   return pipsStepSize * MarketInfo(Symbol(),MODE_TICKSIZE);
}

datetime TimeCurrentLocal(){
   return TimeCurrent()+timelag*60*60;
}

//+------------------------------------------------------------------+
//| Schedule Logic                                                   |
//+------------------------------------------------------------------+

bool CheckSchedule(){
   if(countSchedule>0 && datetimeSchedule<TimeCurrentLocal()){
      switch(typeSchedule){
      case BUY:
         modes[BUY]=modeSchedule;
         break;
      case SELL:
         modes[SELL]=modeSchedule;
         break;
      case BOTH:
         modes[SELL]=modes[BUY]=modeSchedule;
         break;
      }
      ReadSchedule();
      DisplayLabels();
      return true;
   }
   return timeAdjust<TimeCurrent();
}

bool SetSchedule(TYPE type, MODE mode, datetime dt){
//   Print(dt,"/",TimeCurrentLocal());
   if(dt>TimeCurrentLocal() && (countSchedule==0 || dt<datetimeSchedule)){
      datetimeSchedule=dt;
      typeSchedule=type;
      modeSchedule=mode;
      return true;
   }
   return false;
}

MODE StrToMODE(string buf){
   for(int i=0; EnumToString((MODE)i)!="UNDEFINED"; ++i){
      if(EnumToString((MODE)i)==buf)
         return (MODE)i;
   }
   return MODE_UNDEFINED;
}

TYPE StrToTYPE(string buf){
   if(StringFind(buf, "#")==-1){
      for(int i=0; (TYPE)i!=TYPE_UNDEFINED; ++i){
         if(EnumToString((TYPE)i)==buf)
            return (TYPE)i;
      }
   }
   return TYPE_UNDEFINED;
}

datetime ScheduleStrToTime(string buf){
   datetime dt=StrToTime(buf);
   // 時間表記の場合、過去は翌日とする
   if(StringLen(buf)<=5 && dt<=TimeCurrentLocal()){
//      Print("check1");
      dt+=60*60*24;
   }
   return dt;
}

bool ReadSchedule(){
   const string SCHEDULEFILENAME="schedule.txt";
   
   if(FileIsExist(SCHEDULEFILENAME)){
      int fh=FileOpen(SCHEDULEFILENAME, FILE_READ|FILE_CSV, ",");
      if(fh>=0)
      {
         countSchedule=0;
         while(!FileIsEnding(fh)){
            TYPE type=StrToTYPE(FileReadString(fh));
            if(type!=TYPE_UNDEFINED){
               MODE mode=StrToMODE(FileReadString(fh));
               datetime dt=ScheduleStrToTime(FileReadString(fh));
               if(mode!=MODE_UNDEFINED){
                  SetSchedule(type, mode, dt);
                  ++countSchedule;
               }
            }
         }
         FileClose(fh);
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Position Select Logic                                            |
//+------------------------------------------------------------------+

bool CheckNextPosition(int type, double openPrice, double openTime, int count){
   if(((TimeCurrent()-openTime)>MINIMUM_ORDER_SPAN)){
      switch(type){
      case OP_BUY:
         if(count<alertStack-1){
            return Ask < openPrice - GetStepSize();
         }
         else{
            return Ask < openPrice - GetStepSize() && (Close[0]-Low[iLowest(Symbol(), PERIOD_M1, MODE_LOW, RECOVER_SAMPLES)] > recoverThresholdOnAlert*GetStepSize());
         }
      case OP_SELL:
         if(count<alertStack-1){
            return Bid > openPrice + GetStepSize();
         }
         else{
            return Bid > openPrice + GetStepSize() && (High[iHighest(Symbol(), PERIOD_M1, MODE_HIGH, RECOVER_SAMPLES)]-Close[0] > recoverThresholdOnAlert*GetStepSize());
         }
      }
   }
   return false;
}

bool CheckFirstPosition(int type){
   // ANY LOGIC HERE
   return true;
}

bool CheckPosition(int type, int count, int&tickets[]){
   if(count>=maxStack){
      return false;
   }
   else if(count==0){
      return CheckFirstPosition(type);
   }
   else{
      OrderSelectByTicket(tickets[count-1], __FUNCTION__, __LINE__);
      return CheckNextPosition(type, OrderOpenPrice(), OrderOpenTime(), count);
   }
}

//+------------------------------------------------------------------+
//| Decide Order Function                                            |
//+------------------------------------------------------------------+

double GetLotRate(int count){
   double ret=MathFloor(MathPow(STEP_RATE,count));
   return ret>maxLot?maxLot:ret;
}

double CalcTargetProfit(int count, int&tickets[]){
   return count>=alertStack ? 0 : MathPow(2,count-1);
}

double GetBaseLot(int count, int&tickets[], double initialLot){
   if(count>0){
      OrderSelectByTicket(tickets[0], __FUNCTION__, __LINE__);
      return OrderLots();
   }
   return initialLot;
}

//+------------------------------------------------------------------+
//| TP Calculate Function                                             |
//+------------------------------------------------------------------+

bool CalcLiabilities(int count, int&tickets[],double&liability){
   liability=0;

   OrderSelectByTicket(tickets[count-1], __FUNCTION__, __LINE__);
   int type=OrderType();
   double current=OrderOpenPrice();
   for(int i=0;i<count; ++i){
      OrderSelectByTicket(tickets[i], __FUNCTION__, __LINE__);
      liability+=(type==OP_BUY?current-OrderOpenPrice():OrderOpenPrice()-current)*GetLotRate(i);
   }
   return true;
}

bool CalcTPOffset(int count, int&tickets[], double target, double&offset){
   double lot=TOTAL_LOTS[count];
   double liability=0;
   offset = 0;
   if(CalcLiabilities(count, tickets, liability)){
      offset = (target*GetStepSize()*rateProfit - liability)/lot;
      double stopLevel=MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      if(offset<=stopLevel)
         offset=stopLevel;
      return true;
   }
   return false;
}

bool ModifyTP(int ticket, double takeProfit){
   OrderSelectByTicket(ticket, __FUNCTION__, __LINE__);
   if(OrderTakeProfit()==0 || takeProfit>OrderTakeProfit()+TP_SET_MARGIN*GetStepSize() || takeProfit<OrderTakeProfit()-TP_SET_MARGIN*GetStepSize()){
      double openPrice = OrderOpenPrice();
      double stopLoss = OrderStopLoss();
      for(int i=0; i<TRY_COUNT; ++i){
         if(OrderModify(ticket, openPrice, stopLoss, NormalizeDouble( takeProfit , Digits()),OrderExpiration()))
            return true;
      }
      return PrintError(__FUNCTION__,__LINE__);
   }
   return true;
}

bool ModifyTPs(int count, int& tickets[]){
   if(count>1){
      OrderSelectByTicket(tickets[count-1], __FUNCTION__, __LINE__);
      double takeProfit=OrderTakeProfit();
      for(int i=0; i<count-1; ++i){
         if(!ModifyTP(tickets[i], takeProfit)){
            return PrintError(__FUNCTION__,__LINE__);
         }
      }
   }
   return true;
}

bool SetTP(int count, int&tickets[], double targetProfit){
   if(count>0){
      double offset=0;
      if(CalcTPOffset(count, tickets, targetProfit, offset)){
         int ticket=tickets[count-1];
         OrderSelectByTicket(ticket, __FUNCTION__, __LINE__);
         if(ModifyTP(ticket, OrderType()==OP_BUY ? OrderOpenPrice() + offset : OrderOpenPrice() - offset))
            return ModifyTPs(count, tickets);
      }
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Order Control Function                                           |
//+------------------------------------------------------------------+

bool SendOrder(int type, int magicNumber, int&count, int& tickets[], double baseLot){
   if(CheckPosition(type, count, tickets)){
      int ticket = OrderSend(Symbol(), type, GetLotRate(count) * baseLot, type==OP_BUY ? Ask : Bid, SLIP_PAGE, 0, 0, "(" + IntegerToString(count+1) + ")Take it by Leprechaun." ,magicNumber, 0, clrBlue);
      if(ticket!=-1){
         tickets[count++]=ticket;
         if(count>=alertStack) PrintError(__FUNCTION__, __LINE__);// Just send alert. not error.
         return true;
         //return SetTP(count, tickets, CalcTargetProfit(count, tickets));
      }
      PrintError(__FUNCTION__,__LINE__);
      return false;
   }
   return true;
}

bool CloseOrder(int ticket){
   OrderSelectByTicket(ticket, __FUNCTION__, __LINE__);
   if(OrderCloseTime()==0){
      return OrderClose(ticket, OrderLots(), OrderType()==OP_BUY?Bid:Ask, SLIP_PAGE, clrWhite);
   }
   return PrintError(__FUNCTION__,__LINE__);
}

bool CloseOrders(int count, int&tickets[]){
   for(int i=0;i<count; ++i){
      if(!CloseOrder(tickets[count-1-i]))
         return false;
   }
   return true;
}

bool CloseAllOrders(int count, int&tickets[],bool isMailRequired){
   if(CloseOrders(count, tickets)){
      if(!IsTesting() && isMailRequired) SendMail("Stop by the limit","Hi Boss. \r\nIt's your Leprechaun on "+IntegerToString(AccountNumber())+".\r\n I have gaven up some. Let you check it.");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Leprachaun Core Function                                         |
//+------------------------------------------------------------------+

bool IsTPEmpty(int count, int&tickets[]){
   if(count>0){
      OrderSelectByTicket(tickets[count-1], __FUNCTION__, __LINE__);
      return OrderTakeProfit()==0.0;
   }
   return false;
}

bool Tick(int type, MODE mode, int magicNumber, double initialLot, bool forceUpdate){

   if(mode!=DEACTIVE){
      int tickets[MAX_STACK];
      int count;
      if(!CollectTickets(magicNumber, tickets, count))return false;

      switch(mode){
      case CLOSE_ALL:
         return CloseAllOrders(count, tickets, true);
      default:
         if(mode==ACTIVE || count>0){
            if(SendOrder(type, magicNumber, count, tickets, GetBaseLot(count, tickets, initialLot))){
               if( forceUpdate || IsTPEmpty(count, tickets)){
                  if(SetTP(count, tickets, mode==STOP_AT_BREAK_EVEN? 0 : CalcTargetProfit(count, tickets))){
                     timeAdjust=TimeCurrent()+REFRESH_PERIOD;
                     return true;
                  }
                  CloseAllOrders(count, tickets, true);
                  return false;
               }
            }
            return false;
         }
      }
   }
   return true;
}