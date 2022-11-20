//+------------------------------------------------------------------+
//|                                                   Leprechaun.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#define VERSION "1.05"
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

//--- input parameters
enum MODE{ACTIVE, DEACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL};
input int magicNumberBuy=19640429;// Long側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotBuy=0.01;// Long側の初期ロット
input MODE modeBuy=ACTIVE;// Long側のモード

input int magicNumberSell=19671120;// Short側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotSell=0.01;// Short側の初期ロット
input MODE modeSell=ACTIVE;// Short側のモード

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

input double positionStep=0.1;//1ステップ単位 USDJPY
//input double positionStep=0.0007;//1ステップ単位 AUDNZD
input double rateProfit=0.4;//利確の割合 AUDNZD=0.6

input int scheduleStopRequest=-1;//Stop Requestまでの時間
input int scheduleStopAtBreakEven=-1;//Stop At Break Evenまでの時間
input int scheduleCloseAll=-1;//Close Allまでの時間

static double TOTAL_LOTS[MAX_STACK];
static string SCHEDULES[MAX_SCHEDULE];
static MODE modeSchedules[MAX_SCHEDULE];
static datetime datetimeSchedules[MAX_SCHEDULE];


#include <stdlib.mqh> 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
void InitialStatics(){
   TOTAL_LOTS[0]=0;
   for(int i=1; i<MAX_STACK; ++i){
      TOTAL_LOTS[i]=TOTAL_LOTS[i-1]+GetLotRate(i-1);
   }
   ReadSchedule(SCHEDULES);
}

int OnInit(){
//Fail safe
//   if(!IsDemo())
//      return INIT_FAILED;

   if(maxStack>MAX_STACK)
      return INIT_FAILED;

   Print("version=",VERSION);

   InitialStatics();

//   for(int i=0;i<16;++i){
//      Print("GetLotRate=",CalcTotalLots(i)," , ",TOTAL_LOTS[i]);
//   }
//   return (INIT_FAILED);
   if(IsExpertEnabled()){
      Initial(OP_BUY, modeBuy, magicNumberBuy, NormalizeDouble(initialLotBuy , Digits()));
      Initial(OP_SELL, modeSell, magicNumberSell, NormalizeDouble(initialLotSell , Digits()));
   }

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   if(IsExpertEnabled()){
      Tick(OP_BUY, modeBuy, magicNumberBuy, NormalizeDouble(initialLotBuy , Digits()));
      Tick(OP_SELL,modeSell, magicNumberSell, NormalizeDouble(initialLotSell , Digits()));
   }
}

bool SetSchedule(MODE mode, datetime dt){
   static int schedules=0;

   modeSchedules[schedules]=mode;
   datetimeSchedules[schedules]=dt;
   schedules++;
   return true;
}

bool InitSchedules(){
   if(scheduleStopRequest>0){
      SetSchedule(STOP_REQUEST, TimeCurrent()+scheduleStopRequest*60*60);
   }
   if(scheduleStopAtBreakEven>0){
      SetSchedule(STOP_AT_BREAK_EVEN, TimeCurrent()+scheduleStopAtBreakEven*60*60);
   }
   if(scheduleCloseAll>0){
      SetSchedule(CLOSE_ALL, TimeCurrent()+scheduleCloseAll*60*60);
   }
   return true;
}

bool ReadSchedule(string&schedules[]){
   const string SCHEDULEFILENAME="schedule.txt";
   if(FileIsExist(SCHEDULEFILENAME)){
      int fh=FileOpen("schedule.txt", FILE_READ|FILE_CSV);
      if(fh>=0)
      {
         for(int i=0; i<MAX_SCHEDULE && !FileIsEnding(fh); ++i){
            schedules[i] = FileReadString(fh);
         }
         FileClose(fh);
      }
   }
   return true;
}

bool PrintError(string func, int line){
   static int prevError=0;
   
   int error = GetLastError();
   string buf = "ERROR:" + func + "(" + IntegerToString(line) + ")=" + ErrorDescription(error);
   Print(buf);
   if(!IsTesting() && error!=prevError){
      prevError=error;
      SendMail("Found some error","Hi Boss. \r\nIt's your Leprechaun.\r\n I have found some error\"" + buf + "\" on my task. Let you check it.");
   }
   return false;
}

bool OrderSelect(int ticket, string func, int line){
   if(!OrderSelect(ticket, SELECT_BY_TICKET)){
      PrintError(func, line);
      return false;
   }
   return true;
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

bool ModifyTP(int ticket, double takeProfit){
   if(OrderSelect(ticket, SELECT_BY_TICKET)){
      if(OrderTakeProfit()==0 || takeProfit>OrderTakeProfit()+TP_SET_MARGIN*positionStep || takeProfit<OrderTakeProfit()-TP_SET_MARGIN*positionStep){
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
   else{
      return PrintError(__FUNCTION__,__LINE__);
   }
}

bool ModifyTPs(int count, int& tickets[]){
   if(count>1){
      if(OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
         double takeProfit=OrderTakeProfit();
         for(int i=0; i<count-1; ++i){
            if(!ModifyTP(tickets[i], takeProfit)){
               return PrintError(__FUNCTION__,__LINE__);
            }
         }
      }
      else{
         return PrintError(__FUNCTION__,__LINE__);
      }
   }
   return true;
}

bool CheckNextPosition(int type, double openPrice, double openTime, int count){
   if(((TimeCurrent()-openTime)>MINIMUM_ORDER_SPAN)){
      switch(type){
      case OP_BUY:
         if(count<alertStack-1){
            return Ask < openPrice - positionStep;
         }
         else{
            return Ask < openPrice - positionStep && (Close[0]-Low[iLowest(Symbol(), PERIOD_M1, MODE_LOW, RECOVER_SAMPLES)] > recoverThresholdOnAlert*positionStep);
         }
      case OP_SELL:
         if(count<alertStack-1){
            return Bid > openPrice + positionStep;
         }
         else{
            return Bid > openPrice + positionStep && (High[iHighest(Symbol(), PERIOD_M1, MODE_HIGH, RECOVER_SAMPLES)]-Close[0] > recoverThresholdOnAlert*positionStep);
         }
      }
   }
   return false;
}

bool OutOfRange(){
   return Ask > iHigh(Symbol(), PERIOD_M15, iHighest(Symbol(), PERIOD_M15, MODE_HIGH, outOfRangeWatchingHours*4, 1)) || Bid < iLow(Symbol(), PERIOD_M15, iLowest(Symbol(), PERIOD_M15,MODE_LOW, outOfRangeWatchingHours*4, 1));
}

double Range(int hour, int offset=0){
   return iHigh(Symbol(),PERIOD_H1,iHighest(Symbol(), PERIOD_H1,MODE_HIGH, hour, offset))-iLow(Symbol(), PERIOD_H1, iLowest(Symbol(), PERIOD_H1,MODE_LOW, hour, offset));
}

double Trend(int min){
   return Close[0] - iMA(Symbol(), PERIOD_M1, min*60, 0, MODE_SMA, PRICE_CLOSE, 0);
}

bool OutOfFluctuationRange(){
   return Range(rangeWatchingDays*24)>rangeWatchingTolerance*positionStep;
}

bool CheckFirstPosition(int type){
   if(activeTrendControl){
      if(!OutOfFluctuationRange()){
         if(!OutOfRange()){
            return (type==OP_BUY ? Trend(trendWatchPeriod)>=trendThreshold*positionStep : Trend(trendWatchPeriod)<=-trendThreshold*positionStep);
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
      if(OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
         return CheckNextPosition(type, OrderOpenPrice(), OrderOpenTime(), count);
      }
      else{
         return PrintError(__FUNCTION__,__LINE__);
      }
   }
}

double GetLotRate(int count){
   double ret=MathFloor(MathPow(STEP_RATE,count));
   return ret>maxLot?maxLot:ret;
}

bool CalcLiabilities(int count, int&tickets[],double&liability){
   liability=0;

   if(OrderSelect(tickets[count-1],SELECT_BY_TICKET)){
      int type=OrderType();
      double current=OrderOpenPrice();
      for(int i=0;i<count; ++i){
         if(OrderSelect(tickets[i], SELECT_BY_TICKET)){
            liability+=(type==OP_BUY?current-OrderOpenPrice():OrderOpenPrice()-current)*GetLotRate(i);
         }
         else{
            return PrintError(__FUNCTION__,__LINE__);
         }
      }
      return true;
   }
   else{
      return PrintError(__FUNCTION__,__LINE__);
   }
}

bool CalcTPOffset(int count, int&tickets[], double target, double&offset){
   double lot=TOTAL_LOTS[count];
   double liability=0;
   offset = 0;
   if(CalcLiabilities(count, tickets, liability)){
      offset = (target*positionStep*rateProfit - liability)/lot;
      double stopLevel=MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      if(offset<=stopLevel)
         offset=stopLevel;
      return true;
   }
   return false;
}

double CalcTargetProfit(int count, int&tickets[]){
   return count>=alertStack ? 0 : MathPow(2,count-1);
}

bool SetTP(int count, int&tickets[], double targetProfit){
   double offset=0;
   if(CalcTPOffset(count, tickets, targetProfit, offset)){
      int ticket=tickets[count-1];
      if(OrderSelect(ticket, SELECT_BY_TICKET)){
         if(ModifyTP(ticket, OrderType()==OP_BUY ? OrderOpenPrice() + offset : OrderOpenPrice() - offset))
            return ModifyTPs(count, tickets);
      }
   }
   return false;
}

bool SendOrder(int type, int magicNumber, int&count, double baseLot, int& tickets[]){
   if(CheckPosition(type, count, tickets)){
      int ticket = OrderSend(Symbol(), type, GetLotRate(count) * baseLot, type==OP_BUY ? Ask : Bid, SLIP_PAGE, 0, 0, "(" + IntegerToString(count+1) + ")Take it by Leprechaun." ,magicNumber, 0, clrBlue);
      if(ticket!=-1){
         tickets[count++]=ticket;
         if(count>=alertStack) PrintError(__FUNCTION__, __LINE__);// Just send alert. not error.
         if(OrderSelect(ticket, SELECT_BY_TICKET)){
            return SetTP(count, tickets, CalcTargetProfit(count, tickets));
         }
      }
      return PrintError(__FUNCTION__,__LINE__);
   }
   return true;
}

bool CloseOrder(int ticket){
   if(OrderSelect(ticket, SELECT_BY_TICKET)&& OrderCloseTime()==0){
      return OrderClose(ticket, OrderLots(), OrderType()==OP_BUY?Bid:Ask, SLIP_PAGE, clrWhite);
   }
   return PrintError(__FUNCTION__,__LINE__);
}

bool CloseOrders(int count, int&tickets[]){
   for(int i=0;i<count; ++i){
      int ticket=tickets[count-1-i];
      if(OrderSelect(ticket, SELECT_BY_TICKET)&& OrderCloseTime()==0){
         if(!OrderClose(ticket, OrderLots(), OrderType()==OP_BUY?Bid:Ask, SLIP_PAGE, clrWhite)){
            return PrintError(__FUNCTION__,__LINE__);
         }
      }
      else{
         return PrintError(__FUNCTION__,__LINE__);
      }
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

// TPがセットできなかったケースをフォローする
bool RecoverTP(int count, int&tickets[]){
   if(count>0){
      if(OrderSelect(tickets[0], SELECT_BY_TICKET)){
         for(int i=0; i<count; ++i){
            if(OrderSelect(tickets[i], SELECT_BY_TICKET)){
               if(OrderTakeProfit()==0){
                  return SetTP(count, tickets, CalcTargetProfit(count, tickets));
               }
            }
            else{
               return PrintError(__FUNCTION__,__LINE__);
            }
         }
      }
      else{
         return PrintError(__FUNCTION__,__LINE__);
      }
   }
   return true;
}

bool IsActive(MODE mode, int count){
   switch(mode){
   case ACTIVE:
      return true;
   case DEACTIVE:
   default:
      return false;
   case STOP_AT_BREAK_EVEN:
   case STOP_REQUEST:
   case CLOSE_ALL:
      return count>0;
   }
}

bool Initial(int type, MODE mode, int magicNumber, double initialLot){

   int tickets[MAX_STACK];
   ArrayInitialize(tickets, 0);
   
   int count;
   if(CollectTickets(magicNumber, tickets, count)){

      if(mode==CLOSE_ALL && count>0)
         return CloseAllOrders(count, tickets, false);
   
      if(count>0){
         if(OrderSelect(tickets[0],SELECT_BY_TICKET)){
            return SetTP(count, tickets, mode==STOP_AT_BREAK_EVEN? 0 : CalcTargetProfit(count, tickets));
         }
         else{
            return PrintError(__FUNCTION__,__LINE__);
         }
      }
      return true;
   }   
   return false;
}

bool IsTargetDate(datetime current, int year, int month, int day=0){
   return TimeYear(current)==year && TimeMonth(current)==month &&(day==0 || TimeDay(current)==day);
}

double GetBaseLot(int count, int&tickets[], double initialLot){
   if(count>0){
      if(OrderSelect(tickets[0],SELECT_BY_TICKET)){
         return OrderLots();
      }
   }
   return initialLot;
}

bool Tick(int type, MODE mode, int magicNumber, double initialLot){
   if(mode!=DEACTIVE){
      int tickets[MAX_STACK];
      int count;
      if(CollectTickets(magicNumber, tickets, count)){
         switch(mode){
         case CLOSE_ALL:
            return CloseAllOrders(count, tickets, true);
         default:
            return Order(type, mode, magicNumber, count, tickets, initialLot);
         }
      }
      return false;
   }
   return true;
}


bool Order(int type, MODE mode, int magicNumber, int count, int&tickets[], double initialLot){

   if(mode==ACTIVE || count>0){
      if(RecoverTP(count, tickets)){
         return SendOrder(type, magicNumber, count, GetBaseLot(count, tickets, initialLot), tickets);
      }
      return false;
   }
   return true;
}