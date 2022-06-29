//+------------------------------------------------------------------+
//|                                                  Leprechaun2.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#property copyright "NAG"
#property link      "https://sites.google.com/site/hhosaka183"
#property version   "1.10"
#property strict
//--- input parameters
enum MODE{ACTIVE, DEACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL};
input int magicNumberBuy=19640429;
input double initialLotBuy=0.01;
input MODE modeBuy=ACTIVE;
input int alertStackBuy=10;

input int magicNumberSell=19671120;
input double initialLotSell=0.01;
input MODE modeSell=ACTIVE;
input int alertStackSell=10;
input bool activeTrendControl=true;
input double trendThreshold=0.05;

//input double overrunMargin=0.3;
input int maxStack=14;
//input int dangerCheckPeriod=3;
//input double dangerCheckMargin=1.0;

//input bool enableTrail=false;
//input int magicNumberTrail=20011231;
//input double trailLot=0.1;
//input double trailPreRange=0.1;
//input double trailSenseParam=0.1;
//input int trailSencePeriod=120;
//input int trailSenceMargin=3;
//input int range=3;
input double stackThreshold=0.05;
//input double alertOffset=100000;

//input int riskCheckHour=4;
//input int riskCheckCount=5;
//input bool EnableRangeWatcher=true;
//input double rangeOffset=0;

#define MAX_STACK (16)
#define TRY_COUNT (20)
#define SLIP_PAGE (20)
#define MINIMUM_ORDER_SPAN (120)
//#define RANGE_INSPECTION_HOUR (12)
#define BASE_PRICE (100000)

static double baseLots[]={1, 1, 2, 3, 5, 8, 11, 17, 25, 38, 57, 86, 129, 129, 129, 129};
static double tpRates[]={0.04, 0.09, 0.12, 0.15, 0.18, 0.2, 0.22, 0.24, 0.26, 0.24, 0.24, 0.25, 0.25, 0.32, 0.38, 0.42};
static double profits[]={40, 80, 160, 320, 640, 1280, 2560, 5000, 7000, 9000, 12000, 5000, 5000, 5000, 5000, 5000};
static double stackRates[]={0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1};
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

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
}
  
void PrintError(string func, int line){
   int error = GetLastError();
   if(error!=0) Print("ERROR:",func,"(",line,")=",ErrorDescription(error));
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

bool ModifyOrder(int ticket, double stopLoss, double limit){
   if(OrderSelect(ticket, SELECT_BY_TICKET)){
      double openPrice = OrderOpenPrice();
      if(stopLoss==0) stopLoss = OrderStopLoss();
      for(int i=0; i<TRY_COUNT; ++i){
         if(OrderModify(ticket, openPrice, stopLoss, limit,0)){
            return true;
         }
      }
   }
   PrintError(__FUNCTION__,__LINE__);
   return false;
}

bool ModifyOrders(int count, int& tickets[]){
   if(count>1 && OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
      double takeProfit=OrderTakeProfit();
      double stopLoss=OrderStopLoss();
      for(int i=0; i<count-1; ++i){
         ModifyOrder(tickets[i], stopLoss, takeProfit);
      }
   }
   return true;
}

bool GetTotalLots(int count, int&tickets[], double&lot){
   lot=0;
   for(int i=0; i<count; ++i){
      if(OrderSelect(tickets[i],SELECT_BY_TICKET)){
         lot+=OrderLots();
      }
      else{
         return false;
      }
   }
   return true;
}

bool CalcTPOffset(int count, int&tickets[], double target, double&offset){
   double lot;
   if(GetTotalLots(count, tickets, lot)){
      double profit;
      offset = 0;
      if(CalcProfit(count, tickets, profit)){
      //printf("CalcTPOffset count=%d, lots=%f profit=%f Ask=%f Bid=%f",count, lot, profit, Ask,Bid);
         offset = (target - profit)/(lot * BASE_PRICE);
         return true;
      }
   }
   return false;
}

//double CalcTP(int type, double openPrice, int count, int&tickets[]){
//  if(count>=alertStack){
//     double tp;
//     if(CalcTPOffset(count, tickets, 0, tp)){
//        return type==OP_BUY ? Bid+tp : Ask-tp;
//     }
//  }else{
//      return type==OP_BUY ? openPrice+tpRates[count-1] : openPrice-tpRates[count-1];
//  }
//  return openPrice;
//}

//bool IsRiskyPosition(int count, int&tickets[]){
//   if(count>=riskCheckCount){
//      if(OrderSelect(tickets[count-1],SELECT_BY_TICKET)){
//         return (TimeCurrent() - OrderOpenTime())/(60*60) >= riskCheckHour;
//      }
//   }
//   return false;
//}

//bool IsBreakRange(int type, int ticket){
//   if(!EnableRangeWatcher)return false;
//   if(OrderSelect(ticket, SELECT_BY_TICKET)){
//      int holdTime = (int)((TimeCurrent() - OrderOpenTime())/(60*60))+1;
//      switch(type){
//      case OP_BUY:
//         {
//            int index = iLowest(Symbol(), PERIOD_H1, MODE_LOW, RANGE_INSPECTION_HOUR, holdTime);
//            if(index>=0){
//               //printf("Bid=%f, iLow=%f",Bid, iLow(Symbol(), PERIOD_H1, index));
//               return Bid < iLow(Symbol(), PERIOD_H1, index)-rangeOffset;
//            }
//         }
//         break;
//      case OP_SELL:
//         {
//            int index = iHighest(Symbol(), PERIOD_H1, MODE_LOW, RANGE_INSPECTION_HOUR, holdTime);
//            if(index>=0){
//               //printf("Ask=%f, iHigh=%f",Ask, iHigh(Symbol(), PERIOD_H1, index));
//               return Ask > iLow(Symbol(), PERIOD_H1, index)+rangeOffset;
//            }
//         }
//         break;
//      }
//   }
//   PrintError(__FUNCTION__,__LINE__);
//   return false;
//}

bool IsTakeNextPoint(int type, double openPrice, int count, int alertStack){
   switch(type){
   case OP_BUY:
      if(count<alertStack){
         return Ask < openPrice - stackRates[count];
      }
      else{
         return Ask < openPrice - stackRates[count] && Close[1]-Open[1]>stackThreshold;
      }
   case OP_SELL:
      if(count<alertStack){
         return Bid > openPrice + stackRates[count];
      }
      else{
         return Bid > openPrice + stackRates[count] && Open[1]-Close[1]>stackThreshold;
      }
   }
   return false;
}

double CalcTakeProfit(int type, double openPrice, int count, int alertStack){
   switch(type){
   case OP_BUY:
      if(count<alertStack){
         return openPrice+tpRates[count-1];
      }
      else{
         return openPrice+1;
      }
   case OP_SELL:
      if(count<alertStack){
         return openPrice-tpRates[count-1];
      }
      else{
         return openPrice-1;
      }
   }
   return 0;
}

bool IsSafetyPeriod(int type){
   if(activeTrendControl){
      //変動中の逆張り禁止
//      if(Range(24*2)>1.0){
//         switch(type){
//         case OP_BUY:
//            return Trend()>=0;
//         default://case OP_SELL:
//            return Trend()<=0;
//         }
//      }
      switch(type){
      case OP_BUY:
         return Trend()>=trendThreshold;
      default://case OP_SELL:
         return Trend()<=trendThreshold;
      }
   }
   return true;
}

double Range(int hour){
   return High[iHighest(Symbol(), PERIOD_H1,MODE_HIGH, hour, 0)]-Low[iLowest(Symbol(), PERIOD_H1,MODE_LOW, hour, 0)];
}

double Trend(){
   return Close[0] - iMA(Symbol(), PERIOD_M1, 60*24*2, 0, MODE_SMA,PRICE_CLOSE, 0);
}

bool SendOrder(int type, int magicNumber, int&count, int alertStack, double baseLot, int& tickets[]){
   if(count==0 || OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
      if(count>0 && ((TimeCurrent()-OrderOpenTime())<MINIMUM_ORDER_SPAN))return false;// Too quick order
      switch(type){
      case OP_BUY:
         if((count==0 && IsSafetyPeriod(OP_BUY)) || IsTakeNextPoint(OP_BUY, OrderOpenPrice(), count, alertStack)){
            int ticket = OrderSend(Symbol(), OP_BUY, baseLots[count] * baseLot, Ask, SLIP_PAGE, 0, 0, "Take it by Leprechaun1. stack="+IntegerToString(count) ,magicNumber, 0, clrBlue);
            
            if(ticket!=-1){
               tickets[count++]=ticket;
               if(OrderSelect(ticket, SELECT_BY_TICKET)){
                  double openPrice = OrderOpenPrice();
                  if(ModifyOrder(ticket, 0, CalcTakeProfit(OP_BUY, openPrice, count, alertStack))){
                     return true;
                  }
               }
            }
         }
         break;
      case OP_SELL:
         if((count==0 && IsSafetyPeriod(OP_SELL))|| IsTakeNextPoint(OP_SELL, OrderOpenPrice(), count, alertStack)){
            int ticket = OrderSend(Symbol(), OP_SELL, baseLots[count] * baseLot, Bid, SLIP_PAGE, 0, 0, "Take it by Leprechaun1." ,magicNumber, 0, clrRed);
            
            if(ticket!=-1){
               tickets[count++]=ticket;
               if(OrderSelect(ticket, SELECT_BY_TICKET)){
                  double openPrice = OrderOpenPrice();
                  if(ModifyOrder(ticket, 0, CalcTakeProfit(OP_SELL, openPrice, count, alertStack))){
                     return true;
                  }
               }
            }
         }
         break;
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

bool CloseAllOrders(int count, int&tickets[],bool isMailRequired){
   for(int i=0;i<count; ++i){
      int ticket=tickets[i];
      if(OrderSelect(ticket, SELECT_BY_TICKET)&& OrderCloseTime()==0){
         int orderType=OrderType();
         double lot=OrderLots();
         if(!OrderClose(ticket, lot, OrderType()==OP_BUY?Bid:Ask, SLIP_PAGE, clrWhite)){
            PrintError(__FUNCTION__,__LINE__);
         }
      }
      else{
         PrintError(__FUNCTION__,__LINE__);
      }
   }
   if(!IsTesting() && isMailRequired) SendMail("Stop by the limit","Hi Boss. \r\nIt's your Leprechaun.\r\n I have gaven up some. Let you check it.");
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

bool StopAtBreakEven(int count, int&tickets[], double target, bool isMailRequired){
   double profit = 0;

   if(CalcProfit(count, tickets, profit)){
      if(profit>=target){
         return CloseAllOrders(count, tickets, isMailRequired);
      }
   }
   return false;
}

bool ExecuteOrder(int type, int magicNumber, int count, double baseLot, int& tickets[], int alertStack){

   if(count<maxStack){
      if(SendOrder(type, magicNumber, count, alertStack, baseLot, tickets)){
         if(count==maxStack-1)
            CloseOrder(tickets[1]);//TBD
         if(count>=alertStack){
            SendMail("Leprechaun alart you the stack count","Hi Boss. \r\nIt's your Leprechaun.\r\n There are too many stack on it. Let you check it.");
         }
         return ModifyOrders(count, tickets);
      }
   }
   return false;
}

bool IsActive(MODE mode, int count){
   switch(mode){
   case ACTIVE:
      return true;
   case DEACTIVE:
      return false;
   case STOP_AT_BREAK_EVEN:
   case STOP_REQUEST:
   case CLOSE_ALL:
      return count>0;
   default:
      return false;
   }
}

int CalcDay(datetime openTime){
   const int DAY = 60*60*24;
   datetime span=TimeCurrent() - openTime;
   int ret=0;
   for(int i=1; i<span/DAY; ++i){
      switch(TimeDayOfWeek(openTime+DAY*i)){
      case SATURDAY:
      case SUNDAY:
         break;
      default:
         ++ret;
         break;
      }
   }
   return ret;
}

bool IsTargetDate(int year, int month, int day){
   return TimeYear(TimeCurrent())==year && TimeMonth(TimeCurrent())==month && TimeDay(TimeCurrent())==day;
}

//bool IsDangerPeriod(){
//   if(IsTargetDate(2016, 3, 29)) return true;//Debug
//   return High[iHighest( Symbol(), PERIOD_D1, MODE_HIGH, 3, 0)]-Low[iLowest( Symbol(), PERIOD_D1, MODE_LOW, dangerCheckPeriod, 0)] > dangerCheckMargin;
//}

//bool DropPosition(int type, int count, int&tickets[]){
//   if(count>0 && OrderSelect(tickets[count-1], SELECT_BY_TICKET)&& OrderCloseTime()==0){
//      int day = CalcDay(OrderOpenTime());
//      if(day>0){
////         return CloseAllOrders(count, tickets, true);
//         return StopAtBreakEven(count, tickets, -alertOffset * (day-1), true);
//      }
//   }
//   return false;
//}

bool Order(int type, MODE mode, int magicNumber, double initialLot, int alertStack){

   int tickets[MAX_STACK];
   double baseLot=initialLot;
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumber, tickets);
   if(count>0 && OrderSelect(tickets[0],SELECT_BY_TICKET)){
      baseLot=OrderLots();
   }
   
   if(IsActive(mode, count)){

      if((mode==STOP_AT_BREAK_EVEN
            || count>=alertStack)
            && StopAtBreakEven(count, tickets, 0, false))
         return false;

//   if(DropPosition(type, count, tickets))
//      return false;
      
//     if(IsRiskyPosition(count, tickets)
//           && StopAtBreakEven(count, tickets, 0, true))
//           return false;
      if(mode==CLOSE_ALL
         && CloseAllOrders(count, tickets, false))
         return false;

      return ExecuteOrder(type, magicNumber, count, baseLot, tickets, alertStack);
   }
   return false;
}

//bool OrderTrail(){
//   double highest=High[iHighest( Symbol(), PERIOD_M1, MODE_HIGH, trailSencePeriod, trailSenceMargin)];
//   double lowest=Low[iLowest( Symbol(), PERIOD_M1, MODE_LOW, trailSencePeriod, trailSenceMargin)];
//   printf("DEBUG:highest=%f, lowest=%f",highest, lowest);
//   if(highest-lowest<trailPreRange)
//   {
//      if(Close[0] > highest + trailSenseParam){
//         int ticket = OrderSend(Symbol(), OP_BUY, trailLot, Ask, SLIP_PAGE, 0, 0, "Trailing by Leprechaun1." ,magicNumberTrail, 0, clrYellow);
//         if(ticket!=-1){
//            return OrderModify(ticket, trailLot, Close[0]-0.1, Ask+1.0, 0);
//         }
//      } else if(Close[0] < lowest-trailSenseParam){
//         int ticket = OrderSend(Symbol(), OP_SELL, trailLot, Bid, SLIP_PAGE, 0, 0, "Trailing by Leprechaun1." ,magicNumberTrail, 0, clrYellow);
//         if(ticket!=-1){
//            return OrderModify(ticket, trailLot, Close[0]+0.1, Bid-1.0, 0);
//         }
//      }
//   }
//   return false;
//}

//bool ShiftTrail(int ticket){
//   if(OrderSelect(ticket, SELECT_BY_TICKET)){
//      switch(OrderType()){
//      case OP_BUY:
//         if(OrderStopLoss()<Close[0]-(0.1*2)){
//            return OrderModify(ticket, OrderOpenPrice(), Close[0]-0.1, OrderTakeProfit(), 0);
//         }
//      case OP_SELL:
//         if(OrderStopLoss()>Close[0]+(0.1*2)){
//            return OrderModify(ticket, OrderOpenPrice(), Close[0]+0.1, OrderTakeProfit(), 0);
//         }
//      }
//   }
//   return false;
//}

//void Trail(){
//   if(enableTrail){
//      int total = OrdersTotal();
//      for (int i=0 ; i<total; ++i) {
//         if(OrderSelect(i, SELECT_BY_POS)){
//            if (OrderMagicNumber()==magicNumberTrail
//                  && OrderSymbol()==Symbol()){
//               ShiftTrail(OrderTicket());
//               return;
//            }
//         }
//      }
//      OrderTrail();
//   }
//}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   if(IsExpertEnabled()){
      Order(OP_BUY, modeBuy, magicNumberBuy, initialLotBuy, alertStackBuy);
      Order(OP_SELL, modeSell, magicNumberSell, initialLotSell, alertStackSell);
//      Trail();
   }
}
