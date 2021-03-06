//+------------------------------------------------------------------+
//|                                                  Leprechaun2.mq4 |
//|                                                              NAG |
//|                         https://sites.google.com/site/hhosaka183 |
//+------------------------------------------------------------------+
#property copyright "NAG"
#property link      "https://sites.google.com/site/hhosaka183"
#property version   "1.16"
#property strict
//--- input parameters
enum MODE{ACTIVE, DEACTIVE, STOP_REQUEST, STOP_AT_BREAK_EVEN, CLOSE_ALL};
input int magicNumberBuy=19640429;// Long側のマジックナンバー。　すべてのツールでユニークでなければならない。
input double initialLotBuy=0.01;// Long側の初期ロット
input MODE modeBuy=ACTIVE;// Long側のモード

input int magicNumberSell=19671120;// Short側のマジックナンバー。　すべてのツールでユニークでなければならない。
input double initialLotSell=0.01;// Short側の初期ロット
input MODE modeSell=ACTIVE;// Short側のモード
input bool activeTrendControl=true;// トレンドコントロールの使用。　逆張りを抑制します。
input double trendThreshold=0.05;// トレンドコントロールの閾値。値が大きいほどゆるくなります。

input int alertStack=10;// 警戒段数。ブレークイーブンでクローズします。
input int maxStack=14;//論理最大段数。16以下。段数を越えるとき、2番目のポジションを損切りします。
input double recoverThreshold=0.09;// 警戒段を積み上げる閾値。　大きいほど鈍くなります。

input int iParam1=2*24;
input double dParam1=1.0;

#define UNIT_LOT (0.01)
#define MAX_STACK (16)
#define TRY_COUNT (20)
#define SLIP_PAGE (20)
#define MINIMUM_ORDER_SPAN (120)
#define BASE_PRICE (100000)
#define PIPS_RATE (0.001)
#define RECOVER_SAMPLES (5)
#define OUT_OF_RANGE_PERIOD (2*60)

static double baseLots[]={1, 1, 2, 3, 5, 8, 11, 17, 25, 38, 57, 86, 129, 129, 129, 129};
static double targetProfits[]={40, 80, 160, 320, 640, 1280, 2560, 5120, 7000, 9000, 5000, 4000, 3000, 3000, 3000, 3000};
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

   if(ChartPeriod()!=PERIOD_M1)
      return INIT_FAILED;

   if(IsExpertEnabled()){
      Initial(OP_BUY, modeBuy, magicNumberBuy);
      Initial(OP_SELL, modeSell, magicNumberSell);
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
      Order(OP_BUY, modeBuy, magicNumberBuy, initialLotBuy);
      Order(OP_SELL, modeSell, magicNumberSell, initialLotSell);
   }
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

bool ModifyPreviousOrders(int count, int& tickets[]){
   if(count>1 && OrderSelect(tickets[count-1], SELECT_BY_TICKET)){
      double takeProfit=OrderTakeProfit();
      double stopLoss=OrderStopLoss();
      for(int i=0; i<count-1; ++i){
         ModifyOrder(tickets[i], stopLoss, takeProfit);
      }
   }
   return true;
}

bool OutOfRange(int min){
   return Ask > High[iHighest(Symbol(), PERIOD_M1, MODE_HIGH, min, 1)] || Bid < Low[iLowest(Symbol(), PERIOD_M1,MODE_LOW, min, 1)];
}

double Range(int min){
   double ret=High[iHighest(Symbol(), PERIOD_M1,MODE_HIGH, min)]-Low[iLowest(Symbol(), PERIOD_M1,MODE_LOW, min)];
   return ret;
}

double Trend(int min){
   return Close[0] - iMA(Symbol(), PERIOD_M1, min*60, 0, MODE_SMA, PRICE_CLOSE, 0);
}

bool IsNextPosition(int type, double openPrice, double openTime, int count){
   if(((TimeCurrent()-openTime)>MINIMUM_ORDER_SPAN)){
      switch(type){
      case OP_BUY:
         if(count<alertStack-1){
            return Ask < openPrice - stackRates[count];
         }
         else{
            return Ask < openPrice - stackRates[count] && (Close[0]-Low[iLowest(Symbol(), PERIOD_M1, MODE_LOW, RECOVER_SAMPLES)]>recoverThreshold);
         }
      case OP_SELL:
         if(count<alertStack-1){
            return Bid > openPrice + stackRates[count];
         }
         else{
            return Bid > openPrice + stackRates[count] && (High[iHighest(Symbol(), PERIOD_M1, MODE_HIGH, RECOVER_SAMPLES)]-Close[0]>recoverThreshold);
         }
      }
   }
   return false;
}

bool IsFirstPosition(int type){
   if(activeTrendControl){
      if(OutOfRange(OUT_OF_RANGE_PERIOD)) return false;
      switch(type){
      case OP_BUY:
         return Trend(24*2)>=trendThreshold;
      default://case OP_SELL:
         return Trend(24*2)<=trendThreshold;
      }
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
         offset = (target - profit)/(lot * BASE_PRICE) - (MarketInfo(Symbol(), MODE_SPREAD) * PIPS_RATE);
         return true;
      }
   }
   return false;
}

bool SetTP(int type, double currentPrice, int count, int&tickets[], double rate){
   double offset=0;
   if(CalcTPOffset(count, tickets, targetProfits[count-1] * rate, offset)){
      if(offset<=0){
         return CloseAllOrders(count, tickets, false);
      }
      else{
         int ticket=tickets[count-1];
         if(ModifyOrder(ticket, 0, OrderType()==OP_BUY ? currentPrice + offset : currentPrice - offset))
            return ModifyPreviousOrders(count, tickets);
      }
   }
   return false;
}

bool TakeCounterOrder(int ticket){
   if(OrderSelect(ticket, SELECT_BY_TICKET)){
      int type = OrderType()==OP_BUY?OP_SELL : OP_BUY;
      return OrderSend(Symbol(), type, OrderLots(), type ? Ask : Bid, SLIP_PAGE, 0, 0, "Counter Order. Take it by Leprechaun1." ,12345678, 0, clrPink)!=-1;
   }
   return false;
}

bool SendOrder(int type, int magicNumber, int&count, double baseLot, int& tickets[]){
   if(IsTakePosition(type, count, tickets)){
      int ticket = OrderSend(Symbol(), type, baseLots[count] * baseLot, type==OP_BUY ? Ask : Bid, SLIP_PAGE, 0, 0, "Take it by Leprechaun1." ,magicNumber, 0, clrBlue);
      if(ticket!=-1){
         tickets[count++]=ticket;
         if(OrderSelect(ticket, SELECT_BY_TICKET)){
            if(SetTP(type, OrderOpenPrice(), count, tickets, baseLot / UNIT_LOT)){
               if(count==maxStack-1){
                  CloseOrder(tickets[1]);
                  //TakeCounterOrder(tickets[count-1]);
               }
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
bool CheckTP(int type, int count, int&tickets[]){
   if(count>0 && OrderSelect(tickets[0], SELECT_BY_TICKET)){
      double baseLot = OrderLots();
      for(int i=0; i<count; ++i){
         if(OrderSelect(tickets[i], SELECT_BY_TICKET)){
            if(OrderTakeProfit()==0){
               SetTP(type, type==OP_BUY?Bid:Ask, count, tickets, baseLot / UNIT_LOT);
               return true;
            }
         }
      }
   }
   return false;
}

bool ExecuteOrder(int type, int magicNumber, int count, double baseLot, int& tickets[]){

   if(count<maxStack){
      CheckTP(type, count, tickets);
      if(SendOrder(type, magicNumber, count, baseLot, tickets)){
         if(count>=alertStack){
            SendMail("Leprechaun alart you the stack count","Hi Boss. \r\nIt's your Leprechaun.\r\n There are too many stack on it. Let you check it.");
         }
         return true;
      }
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

int GetHoldingDay(int count, int&tickets[]){
   if(count>0 && OrderSelect(tickets[count-1],SELECT_BY_TICKET)){
      return CalcDay(OrderOpenTime());
   }
   return 0;
}

bool Initial(int type, MODE mode, int magicNumber){
   switch(mode){
   case CLOSE_ALL:
      {
         int tickets[MAX_STACK];
         ArrayInitialize(tickets, 0);
         int count = GetTickets(magicNumber, tickets);
         if(count>0){
            return !CloseAllOrders(count, tickets, false);
         }
      }
      break;
   }
   return true;
}

bool Order(int type, MODE mode, int magicNumber, double initialLot){

   int tickets[MAX_STACK];
   double baseLot=initialLot;
   ArrayInitialize(tickets, 0);
   int count = GetTickets(magicNumber, tickets);
   if(count>0 && OrderSelect(tickets[0],SELECT_BY_TICKET)){
      baseLot=OrderLots();
   }
   
   if(IsActive(mode, count)){

      if((mode==STOP_AT_BREAK_EVEN
//         || GetHoldingDay(count, tickets)>0
         || count>=alertStack)
            && StopAtBreakEven(count, tickets, 0, false))
         return false;

      return ExecuteOrder(type, magicNumber, count, baseLot, tickets);
   }
   return false;
}