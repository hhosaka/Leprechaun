//+------------------------------------------------------------------+
//|                                                   Leprechaun.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#define VERSION "1.10"
#property copyright "NAG"
#property link      "https://sites.google.com/site/hhosaka183"
#property version   VERSION
#property strict

#define MAX_STACK (64)
#define MAX_SCHEDULE (64)
#define TRY_COUNT (20)
#define SLIP_PAGE (20)
#define MINIMUM_ORDER_SPAN (120)
#define RECOVER_SAMPLES (5)
#define STEP_RATE (1.5)
#define TP_SET_MARGIN (0.05)
#define REFRESH_PERIOD (60*60)
#define ID_SCHEDULE "schedule"

//--- input parameters
enum MODE{ACTIVE, DEACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL, MODE_UNDEFINED};
enum TYPE{BUY=0, SELL=1, BOTH=2, TYPE_UNDEFINED=3};

input int magicNumberBuy=19640429;// Long側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotBuy=0.01;// Long側の初期ロット
input MODE initialModeBuy=ACTIVE;// Long側のモード

input int magicNumberSell=19671120;// Short側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotSell=0.01;// Short側の初期ロット
input MODE initialModeSell=ACTIVE;// Short側のモード

input bool activeTrendControl=false;// トレンドコントロールの使用
input double trendThreshold=-0.5;// トレンド監視の閾値（ステップ単位）
input int trendWatchPeriod=48;// トレンド監視時間
input int outOfRangeWatchingHours=12;// レンジ逸脱監視時間
input int rangeWatchingDays=6;// 安定レンジ監視日数
input double rangeWatchingTolerance=10;// 許容レンジ幅（ステップ単位）

input int alertStack=10;// 警戒段数。ブレークイーブンでクローズします
input double recoverThresholdOnAlert=0.9;
input int maxStack=MAX_STACK;// 論理最大段数。64以下。
input double maxLot=129;// 許容する最大ロット倍率 AUDNZD=300

input double pipsStepSize=100;//1ステップのサイズの0.1Pips単位
input double rateProfit=0.4;//利確の割合

input int timelag=7;//時差(時間)

static double TOTAL_LOTS[MAX_STACK];
static MODE modeSchedules[2][MAX_SCHEDULE];
static datetime datetimeSchedules[2][MAX_SCHEDULE];
static datetime timeAdjustBuy;
static datetime timeAdjustSell;
static MODE modeBuy;
static MODE modeSell;

#include <stdlib.mqh> 

//+------------------------------------------------------------------+
//| Framework Function                                               |
//+------------------------------------------------------------------+

int OnInit(){
//Fail safe
//   if(!IsDemo())
//      return INIT_FAILED;

   if(maxStack>MAX_STACK)
      return INIT_FAILED;

   Print("version=",VERSION);

   InitialStatics();

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   DestroyLabel(ID_SCHEDULE+EnumToString(BUY));
   DestroyLabel(ID_SCHEDULE+EnumToString(SELL));
}

void OnTick(){
   if(IsExpertEnabled()){
      Tick(OP_BUY, CheckSchedule(BUY, modeBuy), magicNumberBuy, NormalizeDouble(initialLotBuy , Digits()), timeAdjustBuy);
      Tick(OP_SELL, CheckSchedule(SELL, modeSell), magicNumberSell, NormalizeDouble(initialLotSell , Digits()), timeAdjustSell);
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

void DestroyLabel(string id){
   ObjectDelete(id);
}

void SetLabel(string id, string buf){
   ObjectSetText(id, buf, 12, "Meiryo UI", clrYellow);
}

void DisplaySchedule(TYPE type){
   int next=-1;
   int count=0;
   for(int i=0; i<MAX_SCHEDULE; ++i){
      if(datetimeSchedules[type][i]>TimeCurrentLocal()){
         next=i;
         count++;
      }
   }
   SetLabel(ID_SCHEDULE+EnumToString(type),
      EnumToString(type)+":"
      +(next==-1?
         "No Schedule":
         EnumToString(modeSchedules[type][next])
         +"("+TimeToStr(datetimeSchedules[type][next])+")"
         +"["+IntegerToString(count)+"]"));
}

void DisplaySchedules(){
   DisplaySchedule(BUY);
   DisplaySchedule(SELL);
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
   timeAdjustBuy=timeAdjustSell=0;
   modeBuy=initialModeBuy;
   modeSell=initialModeSell;

   CreateLabel(ID_SCHEDULE+EnumToString(BUY), 0, 20);
   CreateLabel(ID_SCHEDULE+EnumToString(SELL), 0, 40);
   DisplaySchedules();
}

bool PrintError(string func, int line){
   static int prevError=0;
   
   int error = GetLastError();
   if(error!=0 && error!=prevError){
      prevError=error;
      string buf = "ERROR:" + func + "(" + IntegerToString(line) + ")=" + ErrorDescription(error);
      Print(buf);
      if(!IsTesting()){
         SendMail("Found some error","Hi Boss. \r\nIt's your Leprechaun.\r\n I have found some error\"" + buf + "\" on my task. Let you check it.");
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

MODE CheckSchedule(TYPE type, MODE&current){
   int index=(int)type;
   for(int i=0; i<MAX_SCHEDULE; ++i){
      if(datetimeSchedules[index][i]!=0 && datetimeSchedules[index][i]<TimeCurrentLocal()){
         datetimeSchedules[index][i]=0;
         DisplaySchedules();
         return current=modeSchedules[index][i];
      }
   }
   return current;
}

bool SetSchedule(int index, int&count, MODE mode, datetime dt){
   if(dt>TimeCurrentLocal()){
      modeSchedules[index][count]=mode;
      datetimeSchedules[index][count]=dt;
      count++;
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

bool ReadSchedule(){
   const string SCHEDULEFILENAME="schedule.txt";
   ArrayInitialize(datetimeSchedules, 0);
   int countBuy=0;
   int countSell=0;
   
   if(FileIsExist(SCHEDULEFILENAME)){
      int fh=FileOpen(SCHEDULEFILENAME, FILE_READ|FILE_CSV, ",");
      if(fh>=0)
      {
         for(int i=0; i<MAX_SCHEDULE && !FileIsEnding(fh); ++i){
            TYPE type=StrToTYPE(FileReadString(fh));
            if(type!=TYPE_UNDEFINED){
               MODE mode=StrToMODE(FileReadString(fh));
               datetime dt=StrToTime(FileReadString(fh));
               if(mode!=MODE_UNDEFINED){
                  switch(type){
                  case BUY:
                     SetSchedule((int)BUY, countBuy, mode, dt);
                     break;
                  case SELL:
                     SetSchedule((int)SELL, countSell, mode, dt);
                     break;
                  case BOTH:
                     SetSchedule((int)BUY, countBuy, mode, dt);
                     SetSchedule((int)SELL, countSell, mode, dt);
                     break;
                  default:
                     break;
                  }
               }
            }
         }
         FileClose(fh);
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Analysis Logic                                                   |
//+------------------------------------------------------------------+

bool OutOfRange(){
   return Ask > iHigh(Symbol(), PERIOD_M15, iHighest(Symbol(), PERIOD_M15, MODE_HIGH, outOfRangeWatchingHours*4, 1)) || Bid < iLow(Symbol(), PERIOD_M15, iLowest(Symbol(), PERIOD_M15,MODE_LOW, outOfRangeWatchingHours*4, 1));
}

double Range(int period, int value, int offset=0){
   return iHigh(Symbol(), period,iHighest(Symbol(), period,MODE_HIGH, value, offset))-iLow(Symbol(), period, iLowest(Symbol(), period,MODE_LOW, value, offset));
}

double Trend(int min){
   return Close[0] - iMA(Symbol(), PERIOD_M1, min*60, 0, MODE_SMA, PRICE_CLOSE, 0);
}

bool OutOfFluctuationRange(){
   return Range(PERIOD_D1, rangeWatchingDays)>rangeWatchingTolerance*GetStepSize();
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
   if(activeTrendControl){
      if(!OutOfFluctuationRange()){
         if(!OutOfRange()){
            return (type==OP_BUY ? Trend(trendWatchPeriod)>=trendThreshold*GetStepSize() : Trend(trendWatchPeriod)<=-trendThreshold*GetStepSize());
         }
      }
      return false;
   }
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
         if(OrderModify(ticket, openPrice, stopLoss, NormalizeDouble( takeProfit , Digits()),0)){
            return true;
         }else{
            return PrintError(__FUNCTION__,__LINE__);
         }
      }
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
      if(!IsTesting() && isMailRequired) SendMail("Stop by the limit","Hi Boss. \r\nIt's your Leprechaun.\r\n I have gaven up some. Let you check it.");
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

bool Tick(int type, MODE mode, int magicNumber, double initialLot, datetime&timeAdjust){

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
               if(IsTPEmpty(count, tickets) || TimeCurrent()>timeAdjust){
                  if(SetTP(count, tickets, mode==STOP_AT_BREAK_EVEN? 0 : CalcTargetProfit(count, tickets))){
                     timeAdjust=TimeCurrent()+REFRESH_PERIOD;
                     return true;
                  }
               }
            }
            return false;
         }
      }
   }
   return true;
}