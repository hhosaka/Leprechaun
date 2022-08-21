//+------------------------------------------------------------------+
//|                                                   Leprechaun.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#property copyright "NAG"
#property link      "https://sites.google.com/site/hhosaka183"
#property version   "1.01"
#property strict

#define UNIT_LOT (0.01)
#define MAX_STACK (64)
#define TRY_COUNT (20)
#define SLIP_PAGE (20)
#define MINIMUM_ORDER_SPAN (120)
#define BASE_PRICE (100000)
#define RECOVER_SAMPLES (5)
#define TAKE_PROFIT_MODIFY_TRESHORD (0.005)
#define STACK_RATE (0.1)
#define RECOVER_THRESHOLD (0.09)

//--- input parameters
enum MODE{ACTIVE, SCHEDULED, DEACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL};
input int magicNumberBuy=19640429;// Long側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotBuy=0.01;// Long側の初期ロット
input MODE modeBuy=ACTIVE;// Long側のモード

input int magicNumberSell=19671120;// Short側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotSell=0.01;// Short側の初期ロット
input MODE modeSell=ACTIVE;// Short側のモード

input int magicNumberCounter=20011231;// カウンターのマジックナンバー。　すべてのツールでユニークでなければならない
input double counterThreshold=0.2;//カウンタートレイル開始閾値
input double counterMargin=0.16;//カウンタートレイルの上昇閾値

input bool activeTrendControl=true;// トレンドコントロールの使用
input double trendThreshold=-0.05;// トレンド監視の閾値
input int trendWatchPeriod=48;// トレンド監視時間
input int outOfRangeWatchingHours=12;// レンジ逸脱監視時間
input int rangeWatchingDays=6;// 安定レンジ監視日数
input double rangeWatchingTolerance=1.0;// 許容レンジ幅

input int alertStack=10;// 警戒段数。ブレークイーブンでクローズします
input int counterStack=10;// カウンタートレイルを開始する段数
input int maxStack=MAX_STACK;// 論理最大段数。16以下。段数を越えるとき、2番目のポジションを損切りする

input int scheduleStart=3;// 取引開始時（サーバ時間）。スケジュールモードのみ有効
input int scheduleStopRequest=11;// 取引停止要求時（サーバ時間）。スケジュールモードのみ有効
input int scheduleBreakEven=13;// ブレイクイーブンモード開始時（サーバ時間）。-1で無効。スケジュールモードのみ有効
input int scheduleCloseAll=-1;// 取引終了時（サーバ時間）。-1で無効。スケジュールモードのみ有効

#include <stdlib.mqh> 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
//Fail safe
//   if(!IsDemo())
//      return INIT_FAILED;

   if(maxStack>MAX_STACK)
      return INIT_FAILED;

   if(ChartPeriod()!=PERIOD_M1)
      return INIT_FAILED;

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
      Order(OP_BUY, ScheduledMode(modeBuy), magicNumberBuy, NormalizeDouble(initialLotBuy , Digits()));
      Order(OP_SELL, ScheduledMode(modeSell), magicNumberSell, NormalizeDouble(initialLotSell , Digits()));
   }
}

void PrintError(string func, int line){
   static int prevError=0;
   
   int error = GetLastError();
   if(error!=0){
      string buf = "ERROR:" + func + "(" + IntegerToString(line) + ")=" + ErrorDescription(error);
      Print(buf);
      if(!IsTesting() && error!=prevError){
         prevError=error;
         SendMail("Found some error","Hi Boss. \r\nIt's your Leprechaun.\r\n I have found some error\"" + buf + "\" on my task. Let you check it.");
      }
   }
}

int GetTickets(int magicNumber, int& tickets[]){
   int ret = 0;
   int total = OrdersTotal();

   for (int i=0 ; i<total; ++i) {
      if(OrderSelect(i, SELECT_BY_POS)){
         if (OrderMagicNumber()==magicNumber
               && OrderSymbol()==Symbol()){
            tickets[ret++]=OrderTicket();
         }
      }
      else{
         PrintError(__FUNCTION__,__LINE__);
      }
   }
   return ret;
}

int AdjustScheduleHour(int startHour, int srcHour){
   return (srcHour+24-startHour)%24;
}

MODE ScheduledMode(MODE mode){
   if(mode==SCHEDULED){
      int now = AdjustScheduleHour(scheduleStart, TimeHour(TimeCurrent()));
      if(now < AdjustScheduleHour(scheduleStart, scheduleStopRequest)){
         return ACTIVE;
      }else if(scheduleBreakEven<0 || now<AdjustScheduleHour(scheduleStart, scheduleBreakEven)){
         return STOP_REQUEST;
      }else if(scheduleCloseAll<0 || now<AdjustScheduleHour(scheduleStart, scheduleCloseAll)){
         return STOP_AT_BREAK_EVEN;
      }else if(scheduleCloseAll>=0 && scheduleCloseAll<24){
         return CLOSE_ALL;
      }else{
         return DEACTIVE;
      }
   }
   return mode;
}

double GetTargetProfit(int count){
   static double profits[]={40, 80, 160, 320, 640, 1280, 2560, 5120, 7000, 9000, 12000, 19000, 24000};
   int size=ArraySize(profits);
   return count<size? profits[count]:profits[size-1];
}

double GetBaseLot(int count){
   static double lots[]={1, 1, 2, 3, 5, 8, 11, 17, 25, 38, 57, 86, 129};
   int size=ArraySize(lots);
   return count<size? lots[count] : lots[size-1];
}

bool ModifyOrder(int ticket, double takeProfit){
   if(OrderSelect(ticket, SELECT_BY_TICKET)){
      if(OrderTakeProfit()==0 || takeProfit>OrderTakeProfit()+TAKE_PROFIT_MODIFY_TRESHORD || takeProfit<OrderTakeProfit()-TAKE_PROFIT_MODIFY_TRESHORD){
         double openPrice = OrderOpenPrice();
         double stopLoss = OrderStopLoss();
         for(int i=0; i<TRY_COUNT; ++i){
            if(OrderModify(ticket, openPrice, stopLoss, NormalizeDouble( takeProfit , Digits()),0)){
               return true;
            }
         }
      }
   }
   PrintError(__FUNCTION__,__LINE__);
   return false;
}

bool ModifyPreviousOrders(int count, int& tickets[]){
   if(count>1 && OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
      double takeProfit=OrderTakeProfit();
      for(int i=0; i<count-1; ++i){
         ModifyOrder(tickets[i], takeProfit);
      }
   }
   return true;
}

bool IsNextPosition(int type, double openPrice, double openTime, int count){
   if(((TimeCurrent()-openTime)>MINIMUM_ORDER_SPAN)){
      switch(type){
      case OP_BUY:
         if(count<alertStack-1){
            return Ask < openPrice - STACK_RATE;
         }
         else{
            return Ask < openPrice - STACK_RATE && (Close[0]-Low[iLowest(Symbol(), PERIOD_M1, MODE_LOW, RECOVER_SAMPLES)] > RECOVER_THRESHOLD);
         }
      case OP_SELL:
         if(count<alertStack-1){
            return Bid > openPrice + STACK_RATE;
         }
         else{
            return Bid > openPrice + STACK_RATE && (High[iHighest(Symbol(), PERIOD_M1, MODE_HIGH, RECOVER_SAMPLES)]-Close[0] > RECOVER_THRESHOLD);
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
   return Range(rangeWatchingDays*24)>rangeWatchingTolerance;
}

bool IsFirstPosition(int type){
   if(activeTrendControl){
      if(OutOfFluctuationRange())return false;
      if(OutOfRange()) return false;
      return (type==OP_BUY ? Trend(trendWatchPeriod)>=trendThreshold : Trend(trendWatchPeriod)<=-trendThreshold);
   }
   return true;
}

bool IsTakePosition(int type, int count, int&tickets[]){
   if(count==0){
      return IsFirstPosition(type);
   }
   else{
      if(OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
         return IsNextPosition(type, OrderOpenPrice(), OrderOpenTime(), count);
      }
   }
   return false;
}

bool CalcTotalLots(int count, int&tickets[], double&lot){
   for(int i=0; i<count; ++i){
      if(!OrderSelect(tickets[i],SELECT_BY_TICKET))
         return false;

      lot+=OrderLots();
   }
   return true;
}

bool CalcProfit(int count, int&tickets[],double&profit){
   profit = 0;
   
   for(int i=0;i<count; ++i){
      if(OrderSelect(tickets[i], SELECT_BY_TICKET)){
         profit+=OrderProfit();
      }
      else{
         PrintError(__FUNCTION__,__LINE__);
         return false;
      }
   }
   return true;
}

bool CalcTPOffset(int count, int&tickets[], double target, double&offset){
   double lot=0;
   if(CalcTotalLots(count, tickets, lot)){
      double profit=0;
      offset = 0;
      if(CalcProfit(count, tickets, profit)){
         offset = (target - profit)/(lot * BASE_PRICE);
         return true;
      }
   }
   return false;
}

bool SetTP(int type, int count, int&tickets[], double baseLot){
   double offset=0;
   if(CalcTPOffset(count, tickets, baseLot==0 ? 0 : GetTargetProfit(count-1) * (baseLot / UNIT_LOT), offset)){
      if(offset<=0){
         return CloseAllOrders(count, tickets, false);
      }
      else{
         int ticket=tickets[count-1];
         double price = type==OP_BUY ? Bid : Ask;
         if(ModifyOrder(ticket, OrderType()==OP_BUY ? price + offset : price - offset))
            return ModifyPreviousOrders(count, tickets);
      }
   }
   return false;
}

bool SendOrder(int type, int magicNumber, int&count, double baseLot, int& tickets[]){
   if(IsTakePosition(type, count, tickets)){
      int ticket = OrderSend(Symbol(), type, GetBaseLot(count) * baseLot, type==OP_BUY ? Ask : Bid, SLIP_PAGE, 0, 0, "(" + IntegerToString(count+1) + ")Take it by Leprechaun." ,magicNumber, 0, clrBlue);
      if(ticket!=-1){
         tickets[count++]=ticket;
         if(OrderSelect(ticket, SELECT_BY_TICKET)){
            if(SetTP(type, count, tickets, count>=alertStack ? 0 : baseLot)){
               return true;
            }
         }
      }
   }
   PrintError(__FUNCTION__,__LINE__);
   return false;
}

bool CloseOrder(int ticket){
   if(OrderSelect(ticket, SELECT_BY_TICKET)&& OrderCloseTime()==0){
      if(OrderClose(ticket, OrderLots(), OrderType()==OP_BUY?Bid:Ask, SLIP_PAGE, clrWhite))
         return true;
   }
   PrintError(__FUNCTION__,__LINE__);
   return false;
}

bool CloseOrders(int count, int&tickets[]){
   for(int i=0;i<count; ++i){
      int ticket=tickets[count-1-i];
      if(OrderSelect(ticket, SELECT_BY_TICKET)&& OrderCloseTime()==0){
         if(!OrderClose(ticket, OrderLots(), OrderType()==OP_BUY?Bid:Ask, SLIP_PAGE, clrWhite)){
            PrintError(__FUNCTION__,__LINE__);
         }
      }
      else{
         PrintError(__FUNCTION__,__LINE__);
      }
   }
   return true;
}

bool CloseOrders(int magicNumber){
   int tickets[MAX_STACK];
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumberCounter, tickets);
   if(count>0)
      return CloseOrders(count, tickets);
   return true;
}

bool CloseAllOrders(int count, int&tickets[],bool isMailRequired){
   CloseOrders(count, tickets);
   CloseOrders(magicNumberCounter);
   if(!IsTesting() && isMailRequired) SendMail("Stop by the limit","Hi Boss. \r\nIt's your Leprechaun.\r\n I have gaven up some. Let you check it.");
   return true;
}

bool StopAtBreakEven(int count, int&tickets[], double target, bool isMailRequired){
   double profit = 0;

   if(CalcProfit(count, tickets, profit)){
      if(profit>=target){
         return CloseAllOrders(count, tickets, isMailRequired);
      }
   }
   return false;
}

// TPがセットできなかったケースをフォローする
bool ResetTP(int type, int count, int&tickets[]){
   if(count>0 && OrderSelect(tickets[0], SELECT_BY_TICKET)){
      double baseLot = OrderLots();
      for(int i=0; i<count; ++i){
         if(OrderSelect(tickets[i], SELECT_BY_TICKET)){
            if(OrderTakeProfit()==0){
               SetTP(type, count, tickets, count>=alertStack? 0 : baseLot);
               return true;
            }
         }
      }
   }
   return false;
}

bool ExecuteOrder(int type, int magicNumber, int count, double baseLot, int& tickets[]){

   ResetTP(type, count, tickets);
   if(count<maxStack && SendOrder(type, magicNumber, count, baseLot, tickets)){
      if(count>=alertStack){
         SendMail("Leprechaun alart you the stack count","Hi Boss. \r\nIt's your Leprechaun.\r\n There are too many stack on it. Let you check it.");
      }
      return true;
   }
   return false;
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

bool IsTargetDate(int year, int month, int day){
   return TimeYear(TimeCurrent())==year && TimeMonth(TimeCurrent())==month && TimeDay(TimeCurrent())==day;
}

bool OrderCounter(int type, double totalLot, int magicNumber){
   int tickets[MAX_STACK];
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumber, tickets);
   
   double lot = 0;
   if(CalcTotalLots(count, tickets, lot)){
      lot = totalLot - lot;
      if(lot>0){
         int counterType = type==OP_BUY? OP_SELL : OP_BUY;
         double price = counterType==OP_BUY ? Ask : Bid;
         int ticket = OrderSend(Symbol(), counterType, lot, price, SLIP_PAGE, 0, 0, "(" + IntegerToString(count+1) + ")Take it by Leprechaun for Counter." ,magicNumber, 0, clrBlue);
         if(ticket!=-1){
            double sl = counterType==OP_BUY ? price - counterMargin : price + counterMargin;
            return OrderModify(ticket, price, sl, 0, 0);
         }
      }
   }
   return false;
}

bool Trail(int ticket){
   if(OrderSelect(ticket, SELECT_BY_TICKET)){
      int type = OrderType();
      switch(OrderType()){
      case OP_BUY:
         if(OrderStopLoss() < Bid - counterMargin * 2){
            return OrderModify(ticket, OrderOpenPrice(), Bid - counterMargin, 0, 0);
         }
         break;
      case OP_SELL:
         if(OrderStopLoss() > Ask + counterMargin * 2){
            return OrderModify(ticket, OrderOpenPrice(), Ask + counterMargin, 0, 0);
         }
         break;
      }
   }
   return false;
}

bool TrailCounter(int magicNumber){
   int tickets[MAX_STACK];
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumber, tickets);

   for(int i=0; i<count; ++i){
      Trail(tickets[i]);
   }
   return true;
}

bool Counter(int type, int count, int&tickets[], int magicNumber){
   
   if(count>=counterStack && (type==OP_BUY ? (Open[0]-Close[0]>counterThreshold):(Close[0]-Open[0]>counterThreshold))){
      double lot=0;
      if(CalcTotalLots(count, tickets, lot)){
         OrderCounter(type, lot, magicNumber);
      }
   }
   return TrailCounter(magicNumber);
}

bool Initial(int type, MODE mode, int magicNumber, double initialLot){

   int tickets[MAX_STACK];
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumber, tickets);

   if(mode==CLOSE_ALL && count>0)
      return CloseAllOrders(count, tickets, false);

   if(count>0 && OrderSelect(tickets[0],SELECT_BY_TICKET))
      SetTP(type, count, tickets, mode==STOP_AT_BREAK_EVEN || count>=alertStack ? 0 : OrderLots());

   return true;
}

bool Order(int type, MODE mode, int magicNumber, double initialLot){

   int tickets[MAX_STACK];
   double baseLot=initialLot;
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumber, tickets);
   if(count>0 && OrderSelect(tickets[0],SELECT_BY_TICKET))
      baseLot=OrderLots();
   
   if(count>0 && mode==CLOSE_ALL && CloseAllOrders(count, tickets, true))
      return true;
      
   if(count>0 && mode==STOP_AT_BREAK_EVEN)
      SetTP(type, count, tickets, 0);

   Counter(type, count, tickets, magicNumberCounter);
   
//   if((mode==STOP_AT_BREAK_EVEN
//      || count>=alertStack)
//         && StopAtBreakEven(count, tickets, 0, false))
//      return true;

   if(IsActive(mode, count)){
      return ExecuteOrder(type, magicNumber, count, baseLot, tickets);
   }
   return false;
}