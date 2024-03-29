//+------------------------------------------------------------------+
//|                                                   Leprechaun.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#property copyright "NAG"
#property link      "https://sites.google.com/site/hhosaka183"
#property version   "1.01"
#property strict

#define MAX_STACK (64)
#define TRY_COUNT (20)
#define SLIP_PAGE (20)
#define MINIMUM_ORDER_SPAN (120)
#define RECOVER_SAMPLES (5)
#define TAKE_PROFIT_MODIFY_TRESHORD (0.005)
#define RECOVER_THRESHOLD (0.9)
#define COUNTER_START_TRESHOLD (2.0)
#define COUNTER_MARGIN (1.6)

//--- input parameters
enum MODE{ACTIVE, SCHEDULED, DEACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL};
input int magicNumberBuy=19640429;// Long側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotBuy=0.01;// Long側の初期ロット
input MODE modeBuy=ACTIVE;// Long側のモード

input int magicNumberSell=19671120;// Short側のマジックナンバー。　すべてのツールでユニークでなければならない
input double initialLotSell=0.01;// Short側の初期ロット
input MODE modeSell=ACTIVE;// Short側のモード

input int magicNumberCounter=20011231;// カウンターのマジックナンバー。　すべてのツールでユニークでなければならない
input int counterStack=10;// カウンタートレイルを開始する段数

input int maxStack=MAX_STACK;// 論理最大段数。64以下。
input int alertStack=10;// 警戒段数。ブレークイーブンでクローズします

input bool activeTrendControl=false; //true;// トレンドコントロールの使用
input double trendThreshold=-0.5;// トレンド監視の閾値。１ステップ単位
input int trendWatchPeriod=48;// トレンド監視時間
input int outOfRangeWatchingHours=12;// レンジ逸脱監視時間
input int rangeWatchingDays=6;// 安定レンジ監視日数
input double rangeWatchingTolerance=10;// 許容レンジ幅。１ステップ単位

input double pricePerLot=100000;//1ロットあたりの価格
input double rangePerStep=0.1;//1ステップ毎のレンジ
input double profitRate=0.4;//利益確定率

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
      Order(OP_BUY, modeBuy, magicNumberBuy, NormalizeDouble(initialLotBuy , Digits()));
      Order(OP_SELL, modeSell, magicNumberSell, NormalizeDouble(initialLotSell , Digits()));
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

bool ArrangeOrders(int count, int& tickets[]){
   if(count>1 && OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
      double takeProfit=OrderTakeProfit();
      for(int i=0; i<count-1; ++i){
         ModifyOrder(tickets[i], takeProfit);
      }
   }
   return true;
}

bool AcceptNextPosition(int type, double openPrice, double openTime, int count){
   if(((TimeCurrent()-openTime)>MINIMUM_ORDER_SPAN)){
      switch(type){
      case OP_BUY:
         if(count<alertStack-1){
            return Ask < openPrice - rangePerStep;
         }
         else{
            return Ask < openPrice - rangePerStep && (Close[0]-Low[iLowest(Symbol(), PERIOD_M1, MODE_LOW, RECOVER_SAMPLES)] > rangePerStep * RECOVER_THRESHOLD);
         }
      case OP_SELL:
         if(count<alertStack-1){
            return Bid > openPrice + rangePerStep;
         }
         else{
            return Bid > openPrice + rangePerStep && (High[iHighest(Symbol(), PERIOD_M1, MODE_HIGH, RECOVER_SAMPLES)]-Close[0] > rangePerStep * RECOVER_THRESHOLD);
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
   return Range(rangeWatchingDays*24)>rangePerStep*rangeWatchingTolerance;
}

bool AcceptFirstPosition(int type){
   if(activeTrendControl){
      if(OutOfFluctuationRange())return false;
      if(OutOfRange()) return false;
      return (type==OP_BUY ? Trend(trendWatchPeriod)>=rangePerStep*trendThreshold : Trend(trendWatchPeriod)<=-rangePerStep*trendThreshold);
   }
   return true;
}

bool AcceptPosition(int type, int count, int&tickets[]){
   if(count==0){
      return AcceptFirstPosition(type);
   }
   else{
      if(OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
         return AcceptNextPosition(type, OrderOpenPrice(), OrderOpenTime(), count);
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
         offset = (target - profit)/(lot * pricePerLot);
         return true;
      }
   }
   return false;
}

double GetTargetProfit(int count){
   double ret= pricePerLot * rangePerStep * profitRate;
   for(int i=0;i<count;++i) ret=ret*2;
   return ret;
}

double CalcTargetProfit(int type, int count, int&tickets[]){
   return count>=alertStack ? 0 : GetTargetProfit(count-1);
}

bool SetTP(int type, int count, int&tickets[], double targetProfit){
   double offset=0;
   if(CalcTPOffset(count, tickets, targetProfit, offset)){
      if(offset<=0){
         return CloseAllOrders(count, tickets, false);
      }
      else{
         int ticket=tickets[count-1];
         if(ModifyOrder(ticket, type==OP_BUY ? Bid + offset : Ask - offset))
            return ArrangeOrders(count, tickets);
      }
   }
   return false;
}

double GetStepLot(int count){
   double ret=1;
   for(int i=0;i<count;++i) ret=ret*1.5;
   return ret;
}

bool SendOrder(int type, int magicNumber, int&count, double baseLot, double targetProfit, int& tickets[]){
   if(AcceptPosition(type, count, tickets)){
      int ticket = OrderSend(Symbol(), type, GetStepLot(count) * baseLot, type==OP_BUY ? Ask : Bid, SLIP_PAGE, 0, 0, "(" + IntegerToString(count+1) + ")Take it by Leprechaun." ,magicNumber, 0, clrBlue);
      if(ticket!=-1){
         tickets[count++]=ticket;
         if(OrderSelect(ticket, SELECT_BY_TICKET)){
            if(SetTP(type, count, tickets, targetProfit*baseLot)){
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

// TPがセットできなかったケースをフォローする
bool ResetTP(int type, int count, int&tickets[]){
   if(count>0 && OrderSelect(tickets[0], SELECT_BY_TICKET)){
      for(int i=0; i<count; ++i){
         if(OrderSelect(tickets[i], SELECT_BY_TICKET)){
            if(OrderTakeProfit()==0){
               SetTP(type, count, tickets, CalcTargetProfit(type, count, tickets)* OrderLots());
               return true;
            }
         }
      }
   }
   return false;
}

bool ExecuteOrder(int type, int magicNumber, int count, double baseLot, int& tickets[], double targetProfit){

   ResetTP(type, count, tickets);
   if(count<maxStack && SendOrder(type, magicNumber, count, baseLot, targetProfit, tickets)){
      if(count>=alertStack){
         SendMail("Leprechaun alart you the stack count","Hi Boss. \r\nIt's your Leprechaun.\r\n There are too many stack on it. Let you check it.");
      }
      return true;
   }
   return false;
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
            double sl = counterType==OP_BUY ? price - rangePerStep*COUNTER_MARGIN : price + rangePerStep*COUNTER_MARGIN;
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
         if(OrderStopLoss() < Bid - rangePerStep*COUNTER_MARGIN * 2){
            return OrderModify(ticket, OrderOpenPrice(), Bid - rangePerStep*COUNTER_MARGIN, 0, 0);
         }
         break;
      case OP_SELL:
         if(OrderStopLoss() > Ask + rangePerStep*COUNTER_MARGIN * 2){
            return OrderModify(ticket, OrderOpenPrice(), Ask + rangePerStep*COUNTER_MARGIN, 0, 0);
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
   
   if(count>=counterStack && (type==OP_BUY ? (Open[0]-Close[0]> rangePerStep*COUNTER_START_TRESHOLD):(Close[0]-Open[0]>rangePerStep*COUNTER_START_TRESHOLD))){
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
      SetTP(type, count, tickets, mode==STOP_AT_BREAK_EVEN? 0 : CalcTargetProfit(type, count, tickets)*OrderLots());

   return true;
}

bool IsTargetDate(datetime current, int year, int month, int day=0){
   return TimeYear(current)==year && TimeMonth(current)==month &&(day==0 || TimeDay(current)==day);
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

bool Order(int type, MODE mode, int magicNumber, double initialLot){

   int tickets[MAX_STACK];
   double baseLot=initialLot;
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumber, tickets);
   if(count>0 && OrderSelect(tickets[0],SELECT_BY_TICKET))
      baseLot=OrderLots();

/***
   datetime tp = TimeCurrent();
   if(count==0 &&
      (IsTargetDate(tp, 2012, 3)
      ||IsTargetDate(tp, 2012, 4)
      ||IsTargetDate(tp, 2012, 5)
      ||IsTargetDate(tp, 2012, 12)
      ||IsTargetDate(tp, 2013, 1)
      ||IsTargetDate(tp, 2013, 3)
      ||IsTargetDate(tp, 2013, 5)
      ||IsTargetDate(tp, 2014, 10)
      ||IsTargetDate(tp, 2014, 11)
      ||IsTargetDate(tp, 2014, 12)
      ||IsTargetDate(tp, 2015, 8)
      ||IsTargetDate(tp, 2016, 1)
      ||IsTargetDate(tp, 2016, 2)
      ||IsTargetDate(tp, 2016, 7)
      ||IsTargetDate(tp, 2020, 3)))
      return false;
***/
/***   
   if(mode==ACTIVE && TimeDayOfWeek(tp)==FRIDAY){
      if(TimeHour(tp)>=23){
         mode=CLOSE_ALL;
      }else if(TimeHour(tp)>=12){
         mode=STOP_AT_BREAK_EVEN;
      }else{
         mode=STOP_REQUEST;
      }
   }
***/

   Counter(type, count, tickets, magicNumberCounter);
   
   if(IsActive(mode, count)){
      return ExecuteOrder(type, magicNumber, count, baseLot, tickets, CalcTargetProfit(type, count+1, tickets));
   }
   return false;
}