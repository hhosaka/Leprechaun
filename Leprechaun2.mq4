//+------------------------------------------------------------------+
//|                                                  Leprechaun2.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#property copyright "NAG"
#property link      "https://sites.google.com/site/hhosaka183"
#property version   "1.05"
#property strict
//--- input parameters
enum MODE{ACTIVE, DEACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL};
input int magicNumberBuy=19640429;
input double initialLotBuy=0.01;
input MODE modeBuy=ACTIVE;
input int magicNumberSell=19671120;
input double initialLotSell=0.01;
input MODE modeSell=ACTIVE;

input int alertStack=10;
input double overrunMargin=0.3;
//input int riskCheckHour=4;
//input int riskCheckCount=5;
//input bool EnableRangeWatcher=true;
//input double rangeOffset=0;

#define MAX_STACK (13)
#define TRY_COUNT (20)
#define SLIP_PAGE (20)
#define MINIMUM_ORDER_SPAN (120)
#define RANGE_INSPECTION_HOUR (12)
#define BASE_PRICE (100000)

//static double baseLots[]={1.0, 1.0, 1.5, 3.4, 5.1, 7.6, 11.4, 17.1, 25.6, 38.4, 57.0, 86.0, 129.0, 194.0, 291.0};
static double baseLots[]={1, 1, 2, 3, 5, 8, 11, 17, 25, 38, 57, 86, 129, 194, 294};
static double tpRates[]={0.04, 0.09, 0.12, 0.15, 0.18, 0.2, 0.22, 0.24, 0.26, 0.24, 0.24, 0.25, 0.27, 0.28, 0.29};
static double stackRates[]={0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1,0.1};
#include <stdlib.mqh> 

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
//Fail safe
//   if(!IsDemo())
//      return INIT_FAILED;

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){
}
  
double GetOrderRate(int type){
   switch(type){
   case OP_BUY:
      return Bid;
   case OP_SELL:
      return Ask;
   }
   PrintError(__FUNCTION__,__LINE__);
   return 0;//shourd be error;
}

void PrintError(string func, int line){
   int error = GetLastError();
   if(error!=0) Print("ERROR:",func,"(",line,")=",ErrorDescription(error));
}

int GetTickets(int magicNumber, int& tickets[], int&lastTicket, double&baseLot){
   int ret = 0;
   datetime last = 0;
   datetime first = TimeCurrent();
   
   baseLot=0.01;
   int total = OrdersTotal();

   for (int i=0 ; i<total; ++i) {
      if(OrderSelect(i, SELECT_BY_POS)){
         if (OrderMagicNumber()==magicNumber
               && OrderSymbol()==Symbol()){
            tickets[ret++]=OrderTicket();
            datetime temp = OrderOpenTime();
            if(last < temp){
               last = temp;
               lastTicket = OrderTicket();
            }
            if(first > temp){
               first = temp;
               baseLot=OrderLots();
            }
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

double GetOverrunMargin(int type){
   switch(type){
   case OP_BUY:
      return -overrunMargin;
   case OP_SELL:
      return overrunMargin;
   }
   return 0;
}

double CalcStopLoss(int count, double openPrice, int type ){
   if(count>=MAX_STACK){
      return openPrice+GetOverrunMargin(type);
   }
   return 0;
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

bool CalcTPOffset(int count, int&tickets[], double target, double&offset){
   double profit;
   double lot=0;
   offset = 0;
   for(int i=0; i<count; ++i){
      if(OrderSelect(tickets[i],SELECT_BY_TICKET)){
         lot+=OrderLots();
      }
   }
   if(CalcProfit(count, tickets, profit)){
      //printf("CalcTPOffset count=%d, lots=%f profit=%f Ask=%f Bid=%f",count, lot, profit, Ask,Bid);
      offset = (target - profit)/(lot * BASE_PRICE);
      return true;
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

bool SendOrder(int type, int magicNumber, int&count, int lastTicket, double baseLot, int& tickets[]){
   if(lastTicket==0 || OrderSelect(lastTicket, SELECT_BY_TICKET)){
      if(lastTicket!=0 && ((TimeCurrent()-OrderOpenTime())<MINIMUM_ORDER_SPAN))return false;// Too quick order
      switch(type){
      case OP_BUY:
         if(lastTicket==0 || Ask < (OrderOpenPrice() - stackRates[count])){
            int ticket = OrderSend(Symbol(), OP_BUY, baseLots[count] * baseLot, Ask, SLIP_PAGE, 0, 0, "Take it by Leprechaun1." ,magicNumber, 0, clrBlue);
            
            if(ticket!=-1){
               tickets[count++]=ticket;
               if(OrderSelect(ticket, SELECT_BY_TICKET)){
                  double openPrice = OrderOpenPrice();
                  if(ModifyOrder(ticket, CalcStopLoss(count,openPrice, OP_BUY), openPrice+tpRates[count-1])){
                     return true;
                  }
               }
            }
         }
         break;
      case OP_SELL:
         if(lastTicket==0 || Bid > (OrderOpenPrice() + stackRates[count]) ){
            int ticket = OrderSend(Symbol(), OP_SELL, baseLots[count] * baseLot, Bid, SLIP_PAGE, 0, 0, "Take it by Leprechaun1." ,magicNumber, 0, clrRed);
            
            if(ticket!=-1){
               tickets[count++]=ticket;
               if(OrderSelect(ticket, SELECT_BY_TICKET)){
                  double openPrice = OrderOpenPrice();
                  if(ModifyOrder(ticket, CalcStopLoss(count,openPrice, OP_SELL), openPrice-tpRates[count-1])){
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

bool CloseAllOrders(int count, int&tickets[],bool isMailRequired){
   for(int i=0;i<count; ++i){
      int ticket=tickets[i];
      if(OrderSelect(ticket, SELECT_BY_TICKET)&& OrderCloseTime()==0){
         int orderType=OrderType();
         double rate=GetOrderRate(orderType);
         double lot=OrderLots();
         if(!OrderClose(ticket, lot, rate, SLIP_PAGE, clrWhite)){
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

bool ExecuteOrder(int type, int magicNumber, int count, int lastTicket, double baseLot, int& tickets[]){

   if(count<MAX_STACK){
      if(SendOrder(type, magicNumber, count, lastTicket, baseLot, tickets)){
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

bool Order(int type, MODE mode, int magicNumber, double initialLot){

   int tickets[MAX_STACK];
   int lastTicket=0;
   double baseLot=0.01;
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumber, tickets, lastTicket, baseLot);
   if(count==0)baseLot=initialLot;
   
   if(IsActive(mode, count)){

      if((mode==STOP_AT_BREAK_EVEN
            || count>=alertStack)
            && StopAtBreakEven(count, tickets, 0, false))
         return false;

//     if(IsRiskyPosition(count, tickets)
//           && StopAtBreakEven(count, tickets, 0, true))
//           return false;

      if(mode==CLOSE_ALL
         && CloseAllOrders(count, tickets, false))
         return false;

      return ExecuteOrder(type, magicNumber, count, lastTicket, baseLot, tickets);
   }
   return false;
}
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   if(IsExpertEnabled()){
      Order(OP_BUY, modeBuy, magicNumberBuy, initialLotBuy);
      Order(OP_SELL, modeSell, magicNumberSell, initialLotSell);
   }
}
