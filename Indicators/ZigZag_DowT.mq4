//+------------------------------------------------------------------+
//|                                                  ZigZag_DowT.mq4 |
//|                   Copyright 2006-2014, MetaQuotes Software Corp. |
//|                                              http://www.mql4.com |
//+------------------------------------------------------------------+
#property copyright "2006-2014, MetaQuotes Software Corp."
#property link      "http://www.mql4.com"

#property version     "1.0"
#property description "元のZigZag.mq4を追加修正しました。"
#property description "Rondo"
#property description "http://fx-dollaryen.seesaa.net/"

#property strict

#property indicator_chart_window
#property indicator_buffers 7
#property indicator_color1  Red
#property indicator_color4  clrBlue
#property indicator_color5  clrRed
#property indicator_color6  clrWhite
#property indicator_color7  clrWhite

#property indicator_width4  3
#property indicator_width5  3
#property indicator_width6  2
#property indicator_width7  2

//---- indicator parameters
input int InpDepth=12;     // Depth
input int InpDeviation=5;  // Deviation
input int InpBackstep=3;   // Backstep

input bool alarm = false;  //アラート機能

input bool PriceLabel = true; //価格表示
input color PriceLabelColor = clrWhite;   //価格の色
input int PriceLabelWidth = 1;   //価格の大きさ

//---- indicator buffers
double ExtZigzagBuffer[];
double ExtHighBuffer[];
double ExtLowBuffer[];

double UpTrendArrow[];
double DownTrendArrow[];
double UpArrow[];
double DownArrow[];

//--- globals
int    ExtLevel=3; // recounting's depth of extremums
string indiName = "ZigZag_DowT";

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBackstep>=InpDepth)
     {
      Print("Backstep cannot be greater or equal to Depth");
      return(INIT_FAILED);
     }
//--- 2 additional buffers
   IndicatorBuffers(5);
//---- drawing settings
   SetIndexStyle(0,DRAW_SECTION);
   SetIndexStyle(1,DRAW_NONE);   
   SetIndexStyle(2,DRAW_NONE);
   SetIndexStyle(3,DRAW_ARROW);
   SetIndexArrow(3,233);
   SetIndexStyle(4,DRAW_ARROW);
   SetIndexArrow(4,234);
   SetIndexStyle(5,DRAW_ARROW);
   SetIndexArrow(5,SYMBOL_ARROWUP);
   SetIndexStyle(6,DRAW_ARROW);
   SetIndexArrow(6,SYMBOL_ARROWDOWN);
   
//---- indicator buffers
   SetIndexBuffer(0,ExtZigzagBuffer);
   SetIndexBuffer(1,ExtHighBuffer);
   SetIndexBuffer(2,ExtLowBuffer);
   SetIndexBuffer(3,UpTrendArrow);
   SetIndexBuffer(4,DownTrendArrow);
   SetIndexBuffer(5,UpArrow);
   SetIndexBuffer(6,DownArrow);
   
   SetIndexEmptyValue(0,0.0);
//---- indicator short name
   IndicatorShortName("ZigZag_DowT("+string(InpDepth)+","+string(InpDeviation)+","+string(InpBackstep)+")");
//---- initialization done 
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Custor indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason){

   objDelete(indiName);

   return;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long& tick_volume[],
                const long& volume[],
                const int& spread[])
  {
   int    i,limit,counterZ,whatlookfor=0;
   int    back,pos,lasthighpos=0,lastlowpos=0;
   double extremum;
   double curlow=0.0,curhigh=0.0,lasthigh=0.0,lastlow=0.0;
//--- check for history and inputs
   if(rates_total<InpDepth || InpBackstep>=InpDepth)
      return(0);
//--- first calculations
   if(prev_calculated==0)
      limit=InitializeAll();
   else 
     {
      //--- find first extremum in the depth ExtLevel or 100 last bars
      i=counterZ=0;
      while(counterZ<ExtLevel && i<100)
        {
         if(ExtZigzagBuffer[i]!=0.0)
            counterZ++;
         i++;
        }
      //--- no extremum found - recounting all from begin
      if(counterZ==0)
         limit=InitializeAll();
      else
        {
         //--- set start position to found extremum position
         limit=i-1;
         //--- what kind of extremum?
         if(ExtLowBuffer[i]!=0.0) 
           {
            //--- low extremum
            curlow=ExtLowBuffer[i];
            //--- will look for the next high extremum
            whatlookfor=1;
           }
         else
           {
            //--- high extremum
            curhigh=ExtHighBuffer[i];
            //--- will look for the next low extremum
            whatlookfor=-1;
           }
         //--- clear the rest data
         for(i=limit-1; i>=0; i--)  
           {
            ExtZigzagBuffer[i]=0.0;  
            ExtLowBuffer[i]=0.0;
            ExtHighBuffer[i]=0.0;
           }
        }
     }
//--- main loop      
   for(i=limit; i>=0; i--)
     {
      //--- find lowest low in depth of bars
      extremum=low[iLowest(NULL,0,MODE_LOW,InpDepth,i)];
      //--- this lowest has been found previously
      if(extremum==lastlow)
         extremum=0.0;
      else 
        { 
         //--- new last low
         lastlow=extremum; 
         //--- discard extremum if current low is too high
         if(low[i]-extremum>InpDeviation*Point)
            extremum=0.0;
         else
           {
            //--- clear previous extremums in backstep bars
            for(back=1; back<=InpBackstep; back++)
              {
               pos=i+back;
               if(ExtLowBuffer[pos]!=0 && ExtLowBuffer[pos]>extremum)
                  ExtLowBuffer[pos]=0.0; 
              }
           }
        } 
      //--- found extremum is current low
      if(low[i]==extremum)
         ExtLowBuffer[i]=extremum;
      else
         ExtLowBuffer[i]=0.0;
      //--- find highest high in depth of bars
      extremum=high[iHighest(NULL,0,MODE_HIGH,InpDepth,i)];
      //--- this highest has been found previously
      if(extremum==lasthigh)
         extremum=0.0;
      else 
        {
         //--- new last high
         lasthigh=extremum;
         //--- discard extremum if current high is too low
         if(extremum-high[i]>InpDeviation*Point)
            extremum=0.0;
         else
           {
            //--- clear previous extremums in backstep bars
            for(back=1; back<=InpBackstep; back++)
              {
               pos=i+back;
               if(ExtHighBuffer[pos]!=0 && ExtHighBuffer[pos]<extremum)
                  ExtHighBuffer[pos]=0.0; 
              } 
           }
        }
      //--- found extremum is current high
      if(high[i]==extremum)
         ExtHighBuffer[i]=extremum;
      else
         ExtHighBuffer[i]=0.0;
     }
//--- final cutting 
   if(whatlookfor==0)
     {
      lastlow=0.0;
      lasthigh=0.0;  
     }
   else
     {
      lastlow=curlow;
      lasthigh=curhigh;
     }
   for(i=limit; i>=0; i--)
     {
      switch(whatlookfor)
        {
         case 0: // look for peak or lawn 
            if(lastlow==0.0 && lasthigh==0.0)
              {
               if(ExtHighBuffer[i]!=0.0)
                 {
                  lasthigh=High[i];
                  lasthighpos=i;
                  whatlookfor=-1;
                  ExtZigzagBuffer[i]=lasthigh;
                 }
               if(ExtLowBuffer[i]!=0.0)
                 {
                  lastlow=Low[i];
                  lastlowpos=i;
                  whatlookfor=1;
                  ExtZigzagBuffer[i]=lastlow;
                 }
              }
             break;  
         case 1: // look for peak
            if(ExtLowBuffer[i]!=0.0 && ExtLowBuffer[i]<lastlow && ExtHighBuffer[i]==0.0)
              {
               ExtZigzagBuffer[lastlowpos]=0.0;
               lastlowpos=i;
               lastlow=ExtLowBuffer[i];
               ExtZigzagBuffer[i]=lastlow;
              }
            if(ExtHighBuffer[i]!=0.0 && ExtLowBuffer[i]==0.0)
              {
               lasthigh=ExtHighBuffer[i];
               lasthighpos=i;
               ExtZigzagBuffer[i]=lasthigh;
               whatlookfor=-1;
              }   
            break;               
         case -1: // look for lawn
            if(ExtHighBuffer[i]!=0.0 && ExtHighBuffer[i]>lasthigh && ExtLowBuffer[i]==0.0)
              {
               ExtZigzagBuffer[lasthighpos]=0.0;
               lasthighpos=i;
               lasthigh=ExtHighBuffer[i];
               ExtZigzagBuffer[i]=lasthigh;
              }
            if(ExtLowBuffer[i]!=0.0 && ExtHighBuffer[i]==0.0)
              {
               lastlow=ExtLowBuffer[i];
               lastlowpos=i;
               ExtZigzagBuffer[i]=lastlow;
               whatlookfor=1;
              }   
            break;               
        }
     }

   //以下追加

   if(rates_total == prev_calculated) return(rates_total);

   objDelete(indiName);

   double UpLowPrice = 0.0, DownHighPrice = 0.0;
   double Buffer2 = 0.0, Buffer1 = 0.0, Buffer = 0.0;
   double maxPrice = 0.0, minPrice = 0.0;
   bool boolUp = true;
   int index = 0;
   
   for(i=Bars-1; i>0; i--){

      UpTrendArrow[i] = EMPTY_VALUE;
      DownTrendArrow[i] = EMPTY_VALUE;
      UpArrow[i] = EMPTY_VALUE;
      DownArrow[i] = EMPTY_VALUE;

      if(ExtZigzagBuffer[i] != 0.0){
      
         Buffer2 = Buffer1;
         Buffer1 = ExtZigzagBuffer[i];
         
         if(Buffer2 != 0.0 && UpLowPrice==0.0 && DownHighPrice==0.0){
         
            UpLowPrice = MathMin(Buffer1, Buffer2);
            DownHighPrice = MathMax(Buffer1, Buffer2);
            
            continue;
         }
         
         if(PriceLabel) Label(indiName+string(i), i, ExtZigzagBuffer[i], PriceLabelColor, PriceLabelWidth);
      }
   
      if(Buffer2 == 0) continue;
   
      if(boolUp && UpLowPrice > Close[i]){

         boolUp = false;
         DownTrendArrow[i] = High[i];
         DownHighPrice = maxPrice;
         Buffer = minPrice; 
         
         Line(indiName+"_Line", index, minPrice, clrGray, 1, 1);
         
         if(alarm && i==1) Alert("DOWN Trend Start!");
         
         continue;
      }
      
      if(!boolUp && DownHighPrice < Close[i]){
      
         boolUp = true;
         UpTrendArrow[i] = Low[i];
         UpLowPrice = minPrice;
         Buffer = maxPrice;
         
         Line(indiName+"_Line", index, maxPrice, clrGray, 1, 1);
         
         if(alarm && i==1) Alert("UP Trend Start!");
         
         continue;
         
      }
      
      if(boolUp && maxPrice < Close[i] && Buffer != maxPrice){
      
         UpArrow[i] = Low[i];
         Buffer = maxPrice;
         
         if(alarm && i==1) Alert("Long Entry Chance!");
      }
      
      if(!boolUp && minPrice > Close[i] && Buffer != minPrice){
      
         DownArrow[i] = High[i];
         Buffer = minPrice;
         
         if(alarm && i==1) Alert("Short Entry Chance!");
      }      

      maxPrice = MathMax(Buffer1, Buffer2);
      minPrice = MathMin(Buffer1, Buffer2);
      
      if(boolUp && DownHighPrice < maxPrice){
      
         DownHighPrice = maxPrice;
         UpLowPrice = minPrice;
         
         Line(indiName+"_Line", index, minPrice, clrGray, 1, 1);
      }
      
      if(!boolUp && UpLowPrice > minPrice){
      
         DownHighPrice = maxPrice;
         UpLowPrice = minPrice;
         
         Line(indiName+"_Line", index, maxPrice, clrGray, 1, 1);
      }
      
      if(ExtZigzagBuffer[i] != 0.0) index = i;

   }

//--- done
   return(rates_total);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int InitializeAll()
  {
   ArrayInitialize(ExtZigzagBuffer,0.0);
   ArrayInitialize(ExtHighBuffer,0.0);
   ArrayInitialize(ExtLowBuffer,0.0);
   
//--- first counting position
   return(Bars-InpDepth);
  }
//+------------------------------------------------------------------+

//以下追加
void Label(string Label_name, int position, double price, color Label_color, int Label_width){
   
   long current_chart_id = ChartID();
   
   if (ObjectFind(Label_name) >= 0) ObjectDelete(current_chart_id, Label_name);
   
   ObjectCreate(current_chart_id, Label_name, OBJ_ARROW_LEFT_PRICE, 0, Time[position], price);   
   ObjectSetInteger(current_chart_id, Label_name, OBJPROP_COLOR, Label_color);
   ObjectSetInteger(current_chart_id, Label_name, OBJPROP_WIDTH, Label_width);
   ObjectSetInteger(current_chart_id, Label_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(current_chart_id, Label_name, OBJPROP_HIDDEN, true);
}

void Line(string Line_name, int position, double price, color Line_color, int Line_style, int Line_width){
   
   long current_chart_id = ChartID();
   
   if (ObjectFind(Line_name) != 0) {
   
      ObjectCreate(current_chart_id, Line_name, OBJ_TREND, 0, Time[position], price, Time[0], price);
      ObjectSetInteger(current_chart_id, Line_name, OBJPROP_COLOR, Line_color);
      ObjectSetInteger(current_chart_id, Line_name, OBJPROP_STYLE, Line_style);
      ObjectSetInteger(current_chart_id, Line_name, OBJPROP_WIDTH, Line_width);
      ObjectSetInteger(current_chart_id, Line_name, OBJPROP_BACK, false);
      //ObjectSetInteger(current_chart_id, Line_name, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(current_chart_id, Line_name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(current_chart_id, Line_name, OBJPROP_HIDDEN, true);
   }
   else{
      ObjectMove(Line_name, 0, Time[position], price);
      ObjectMove(Line_name, 1, Time[0], price);
      
   }
   
   ChartRedraw(current_chart_id);
}

void objDelete(string basicName){

   for(int i=ObjectsTotal();i>=0;i--){
      string ObjName = ObjectName(i);
      if(StringFind(ObjName, basicName) >=0) ObjectDelete(ObjName);
   }

}