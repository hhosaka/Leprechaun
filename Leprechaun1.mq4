//+------------------------------------------------------------------+
//|                                                  Leprechaun1.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#property copyright "NAG"
#property link      "https://sites.google.com/site/hhosaka183"
#property version   "1.07"
#property strict
//--- input parameters
input double initialLot=0.01;
enum POSITION {LONG, SHORT};
input POSITION initialPosition;
enum MODE{ACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL};
input MODE mode;
input int alertStack=10;
input double overrunMargin=0.3;
input int magicNumber=19640429;

#define MAX_STACK (12)
#define STEP (0.10)
#define TRY_COUNT (20)
#define SLIP_PAGE (20)
#define MINIMUM_ORDER_SPAN (120)

static int POWER[]={1, 1, 2, 3, 5, 7, 11, 17, 25, 38, 57, 86};
static double tpRates[]={0.04, 0.09, 0.12, 0.15, 0.18, 0.2, 0.24, 0.24, 0.24, 0.24, 0.24, 0.24};

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
  
int GetType(int ticket){
   if(ticket==0){
      switch(initialPosition){
      case LONG:
         return OP_BUY;
      case SHORT:
         return OP_SELL;
      }
   }else if(OrderSelect(ticket, SELECT_BY_TICKET)){
      return OrderType();
   }
   return -1;
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

int GetTickets(int& tickets[], int&lastTicket, double&baseLot){
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

bool SendOrder(int&count, int lastTicket, double baseLot, int& tickets[]){
   if(lastTicket==0 || OrderSelect(lastTicket, SELECT_BY_TICKET)){
      if(lastTicket!=0 && ((TimeCurrent()-OrderOpenTime())<MINIMUM_ORDER_SPAN))return false;// Too quick order
      switch(GetType(lastTicket)){
      case OP_BUY:
         if(lastTicket==0 || Ask < (OrderOpenPrice() - STEP)){
            int ticket = OrderSend(Symbol(), OP_BUY, POWER[count] * baseLot, Ask, SLIP_PAGE, 0, 0, "Take it by Leprechaun1." ,magicNumber, 0, clrBlue);
            
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
         if(lastTicket==0 || Bid > (OrderOpenPrice() + STEP) ){
            int ticket = OrderSend(Symbol(), OP_SELL, POWER[count] * baseLot, Bid, SLIP_PAGE, 0, 0, "Take it by Leprechaun1." ,magicNumber, 0, clrBlue);
            
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
      if(OrderSelect(ticket, SELECT_BY_TICKET && OrderCloseTime()==0)){
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
   if(isMailRequired) SendMail("Stop by the limit","Hi Boss. \r\nIt's your Leprechaun.\r\n I have gaven up some. Let you check it.");
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

bool StopAtBreakEven(int count, int&tickets[], bool isMailRequired){
   double profit = 0;

   if(CalcProfit(count, tickets, profit)){
      if(profit>=0){
         return CloseAllOrders(count, tickets, isMailRequired);
      }
   }
   return false;
}

bool ExecuteOrder(int count, int lastTicket, double baseLot, int& tickets[]){
   if(count<MAX_STACK){
      if(SendOrder(count, lastTicket, baseLot, tickets)){
         if(count>=alertStack){
            SendMail("Leprechaun alart you the stack count","Hi Boss. \r\nIt's your Leprechaun.\r\n There are too many stack on it. Let you check it.");
         }
         return ModifyOrders(count, tickets);
      }
   }
   return false;
}

bool Order(){
   int tickets[MAX_STACK];
   int lastTicket=0;
   double baseLot=0.01;
   ArrayInitialize(tickets, 0);
   int count = GetTickets(tickets, lastTicket, baseLot);

   switch(mode){
   case STOP_REQUEST:
      if(count==0)return false;
      //fall therough
   case ACTIVE:
      if(count==0)
         baseLot=initialLot;
      if(count>=alertStack && StopAtBreakEven(count, tickets, true))return false;
      return ExecuteOrder(count, lastTicket, baseLot, tickets);
   case STOP_AT_BREAK_EVEN:
      if(count!=0){
         return StopAtBreakEven(count, tickets, false);
      }
      break;
   case CLOSE_ALL:
      return CloseAllOrders(count, tickets, false);
   }
   return false;
}
  
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){
   if(IsExpertEnabled()){
      Order();
   }
}
