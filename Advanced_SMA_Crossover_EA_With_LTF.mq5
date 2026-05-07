//+------------------------------------------------------------------+
//|                        Advanced_SMA_Crossover_EA_With_LTF.mq5 |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "2.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- Input Parameters
input group "🔹 CORE SETTINGS"
input ENUM_TIMEFRAMES    ExecutionTF         = PERIOD_H1;      // Execution Timeframe
input ENUM_TIMEFRAMES    LowerTF              = PERIOD_M15;     // Lower Timeframe
input ulong              MagicNumber          = 12345;          // Magic Number
input ulong              LowerTFMagicNumber   = 67890;          // Lower TF Magic Number
input double             LotSize              = 0.1;             // Lot Size
input int                NumberOfTradesPerSignal = 3;             // Number of Trades Per Signal
input bool               UseCandleCloseEntry  = true;            // Use Candle Close Entry
input bool               EnableLowerTFTrading = true;           // Enable Lower TF Trading

input group "🔹 STEP INDEX TRADING"
input bool               TradeStepIndex       = true;            // Trade Step Index 600
input ulong              StepIndexMagicNumber   = 600600;          // Step Index Magic Number
input bool               TradeStepIndex200   = true;            // Trade Step Index 200
input ulong              StepIndex200MagicNumber   = 200200;          // Step Index 200 Magic Number
input bool               TradeStepIndex300   = true;            // Trade Step Index 300
input ulong              StepIndex300MagicNumber   = 300300;          // Step Index 300 Magic Number
input bool               TradeStepIndex400   = true;            // Trade Step Index 400
input ulong              StepIndex400MagicNumber   = 400400;          // Step Index 400 Magic Number
input bool               TradeStepIndex500   = true;            // Trade Step Index 500
input ulong              StepIndex500MagicNumber   = 500500;          // Step Index 500 Magic Number

input group "🔹 BASKET PROFIT SETTINGS"
input bool               EnableBasketProfit  = false;           // Enable Basket Profit Taking
input double             BasketProfitTarget  = 100.0;           // Basket Profit Target (USD)

input group "🔹 MA SETTINGS"
input ENUM_MA_METHOD     MAType               = MODE_SMA;         // MA Type (SMA/EMA)
input int                SMAPeriod            = 28;              // Main MA Period
input int                TrendSMAPeriod      = 50;              // Trend Filter MA Period
input bool               UseTrendFilter       = true;            // Use Trend Filter

input group "🔹 LOWER TF MA SETTINGS"
input ENUM_MA_METHOD     LowerTF_MAType        = MODE_SMA;         // Lower TF MA Type (SMA/EMA)
input int                LowerTF_SMAPeriod     = 14;              // Lower TF MA Period

input group "🔹 STOP LOSS SETTINGS"
input bool               TrailSLOnCandleClose = true;            // Trail SL on Candle Close Only

input group "🔹 AO DIVERGENCE FILTER"
input bool               EnableAODivergence   = false;           // Enable AO Divergence Filter
input bool               EnableHiddenDivergence = false;         // Enable Hidden Divergence
input int                AOSwingLookback      = 10;              // AO Swing Lookback

input group "🔹 ATR VOLATILITY FILTER"
input bool               EnableATRFilter      = false;           // Enable ATR Volatility Filter
input int                ATRPeriod            = 14;              // ATR Period
input double             ATRMinThreshold      = 0.0010;          // ATR Minimum Threshold
input bool               UseRelativeATR       = false;           // Use Relative ATR Mode
input int                ATRRelativeLookback  = 20;              // ATR Relative Lookback
input bool               EnableRangeDetection = false;           // Enable Range Detection
input int                RangeContractionBars = 3;               // Range Contraction Bars

input group "🔹 CHOCH/BOS SNIPER MODE"
input bool               EnableSniperMode     = false;           // Enable CHoCH/BOS Sniper Mode
input bool               EnableRetestEntry    = false;           // Enable Retest Entry
input int                StructureLookback    = 20;              // Structure Lookback

//--- Global Variables
CTrade            trade;
CPositionInfo     position;
CAccountInfo      account;

//--- Indicator Handles
int               smaHighHandle;
int               smaLowHandle;
int               smaCloseHandle;
int               trendSMAHandle;
int               aoHandle;
int               atrHandle;

//--- Lower TF Indicator Handles
int               lowerSmaHighHandle;
int               lowerSmaLowHandle;
int               lowerSmaCloseHandle;

//--- Indicator Buffers
double            smaHighBuffer[];
double            smaLowBuffer[];
double            smaCloseBuffer[];
double            trendSMABuffer[];
double            aoBuffer[];
double            atrBuffer[];

//--- Lower TF Indicator Buffers
double            lowerSmaHighBuffer[];
double            lowerSmaLowBuffer[];
double            lowerSmaCloseBuffer[];

//--- Price Buffers
double            highBuffer[];
double            lowBuffer[];
double            closeBuffer[];
double            openBuffer[];

//--- Lower TF Price Buffers
double            lowerHighBuffer[];
double            lowerLowBuffer[];
double            lowerCloseBuffer[];
double            lowerOpenBuffer[];

//--- State Variables
datetime          lastBarTime;
datetime          lastLowerBarTime;
bool              lastAboveSMA = false;
bool              lastLowerAboveSMA = false;
int               currentTrades = 0;
int               currentLowerTrades = 0;

//--- Higher TF Trend Direction
int               higherTF_Trend = 0; // 1 = uptrend, -1 = downtrend, 0 = neutral

//--- Basket Profit Tracking
double            basketProfit = 0.0;

//--- Structure Arrays
int               swingHighs[];
int               swingLows[];
double            swingHighPrices[];
double            swingLowPrices[];

//--- Step Index State Tracking (for candle close entry)
datetime          lastStepIndexBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize trade object
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_IOC);
   
   //--- Create indicators
   smaHighHandle = iMA(_Symbol, ExecutionTF, SMAPeriod, 0, MAType, PRICE_HIGH);
   smaLowHandle = iMA(_Symbol, ExecutionTF, SMAPeriod, 0, MAType, PRICE_LOW);
   smaCloseHandle = iMA(_Symbol, ExecutionTF, SMAPeriod, 0, MAType, PRICE_CLOSE);
   
   if(UseTrendFilter)
      trendSMAHandle = iMA(_Symbol, ExecutionTF, TrendSMAPeriod, 0, MAType, PRICE_CLOSE);
   
   aoHandle = iAO(_Symbol, ExecutionTF);
   atrHandle = iATR(_Symbol, ExecutionTF, ATRPeriod);
   
   //--- Create Lower TF indicators
   lowerSmaHighHandle = iMA(_Symbol, LowerTF, LowerTF_SMAPeriod, 0, LowerTF_MAType, PRICE_HIGH);
   lowerSmaLowHandle = iMA(_Symbol, LowerTF, LowerTF_SMAPeriod, 0, LowerTF_MAType, PRICE_LOW);
   lowerSmaCloseHandle = iMA(_Symbol, LowerTF, LowerTF_SMAPeriod, 0, LowerTF_MAType, PRICE_CLOSE);
   
   //--- Validate handles
   if(smaHighHandle == INVALID_HANDLE || smaLowHandle == INVALID_HANDLE || 
      smaCloseHandle == INVALID_HANDLE || aoHandle == INVALID_HANDLE || 
      atrHandle == INVALID_HANDLE || lowerSmaHighHandle == INVALID_HANDLE ||
      lowerSmaLowHandle == INVALID_HANDLE || lowerSmaCloseHandle == INVALID_HANDLE)
   {
      Print("Error creating core indicators");
      return(INIT_FAILED);
   }
   
   if(UseTrendFilter && trendSMAHandle == INVALID_HANDLE)
   {
      Print("Error creating trend filter SMA");
      return(INIT_FAILED);
   }
   
   //--- Set array indexing
   ArraySetAsSeries(smaHighBuffer, true);
   ArraySetAsSeries(smaLowBuffer, true);
   ArraySetAsSeries(smaCloseBuffer, true);
   ArraySetAsSeries(trendSMABuffer, true);
   ArraySetAsSeries(aoBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(highBuffer, true);
   ArraySetAsSeries(lowBuffer, true);
   ArraySetAsSeries(closeBuffer, true);
   ArraySetAsSeries(openBuffer, true);
   
   //--- Set Lower TF array indexing
   ArraySetAsSeries(lowerSmaHighBuffer, true);
   ArraySetAsSeries(lowerSmaLowBuffer, true);
   ArraySetAsSeries(lowerSmaCloseBuffer, true);
   ArraySetAsSeries(lowerHighBuffer, true);
   ArraySetAsSeries(lowerLowBuffer, true);
   ArraySetAsSeries(lowerCloseBuffer, true);
   ArraySetAsSeries(lowerOpenBuffer, true);
   
   //--- Initialize structure arrays
   ArrayResize(swingHighs, StructureLookback);
   ArrayResize(swingLows, StructureLookback);
   ArrayResize(swingHighPrices, StructureLookback);
   ArrayResize(swingLowPrices, StructureLookback);
   
   lastBarTime = iTime(_Symbol, ExecutionTF, 0);
   lastLowerBarTime = iTime(_Symbol, LowerTF, 0);
   lastStepIndexBarTime = 0;
   
   Print("Advanced SMA Crossover EA with LTF initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Release indicator handles
   if(smaHighHandle != INVALID_HANDLE) IndicatorRelease(smaHighHandle);
   if(smaLowHandle != INVALID_HANDLE) IndicatorRelease(smaLowHandle);
   if(smaCloseHandle != INVALID_HANDLE) IndicatorRelease(smaCloseHandle);
   if(trendSMAHandle != INVALID_HANDLE) IndicatorRelease(trendSMAHandle);
   if(aoHandle != INVALID_HANDLE) IndicatorRelease(aoHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(lowerSmaHighHandle != INVALID_HANDLE) IndicatorRelease(lowerSmaHighHandle);
   if(lowerSmaLowHandle != INVALID_HANDLE) IndicatorRelease(lowerSmaLowHandle);
   if(lowerSmaCloseHandle != INVALID_HANDLE) IndicatorRelease(lowerSmaCloseHandle);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check if we have enough data
   int requiredBars = MathMax(SMAPeriod, TrendSMAPeriod) + MathMax(ATRPeriod, StructureLookback) + 10;
   if(Bars(_Symbol, ExecutionTF) < requiredBars || Bars(_Symbol, LowerTF) < requiredBars)
      return;
   
   //--- Update all buffers
   if(!UpdateAllBuffers())
      return;
   
   //--- CHECK BASKET PROFIT TARGET FIRST - before any trading
   if(CheckBasketProfitTarget())
   {
      Print("Basket profit target reached: ", basketProfit, " >= ", BasketProfitTarget);
      CloseAllBasketTrades();
      return; // Exit OnTick after closing all trades
   }
   
   //--- Count current trades
   currentTrades = CountCurrentTrades();
   currentLowerTrades = CountCurrentLowerTrades();
   
   //--- Check for new bar
   datetime currentBarTime = iTime(_Symbol, ExecutionTF, 0);
   datetime currentLowerBarTime = iTime(_Symbol, LowerTF, 0);
   bool isNewBar = (currentBarTime != lastBarTime);
   bool isNewLowerBar = (currentLowerBarTime != lastLowerBarTime);
   
   //--- Execute logic based on settings
   if(UseCandleCloseEntry)
   {
      if(isNewBar)
      {
         CheckTradeSignals();
         if(TrailSLOnCandleClose)
            TrailSL();
         lastBarTime = currentBarTime;
      }
      
      if(EnableLowerTFTrading && isNewLowerBar)
      {
         CheckLowerTFSignals();
         lastLowerBarTime = currentLowerBarTime;
      }
      
      //--- Check step index signals on new bar (all enabled symbols)
      if(isNewBar && CanTradeStepIndex())
      {
         CheckAllStepIndexSignals();
      }
   }
   else
   {
      CheckTradeSignals();
      if(EnableLowerTFTrading)
         CheckLowerTFSignals();
      
      //--- Check step index signals (all enabled symbols)
      if(CanTradeStepIndex())
      {
         CheckAllStepIndexSignals();
      }
      
      if(TrailSLOnCandleClose && isNewBar)
         TrailSL();
      else if(!TrailSLOnCandleClose)
         TrailSL();
   }
}

//+------------------------------------------------------------------+
//| Update all indicator and price buffers                            |
//+------------------------------------------------------------------+
bool UpdateAllBuffers()
{
   int bufferSize = StructureLookback + 50;
   
   //--- Copy SMA data
   if(CopyBuffer(smaHighHandle, 0, 0, 3, smaHighBuffer) < 3 ||
      CopyBuffer(smaLowHandle, 0, 0, 3, smaLowBuffer) < 3 ||
      CopyBuffer(smaCloseHandle, 0, 0, 3, smaCloseBuffer) < 3)
      return false;
   
   //--- Copy Lower TF SMA data
   if(CopyBuffer(lowerSmaHighHandle, 0, 0, 3, lowerSmaHighBuffer) < 3 ||
      CopyBuffer(lowerSmaLowHandle, 0, 0, 3, lowerSmaLowBuffer) < 3 ||
      CopyBuffer(lowerSmaCloseHandle, 0, 0, 3, lowerSmaCloseBuffer) < 3)
      return false;
   
   //--- Copy trend filter data if enabled
   if(UseTrendFilter)
   {
      if(CopyBuffer(trendSMAHandle, 0, 0, 3, trendSMABuffer) < 3)
         return false;
   }
   
   //--- Copy AO and ATR data
   if(CopyBuffer(aoHandle, 0, 0, bufferSize, aoBuffer) < bufferSize ||
      CopyBuffer(atrHandle, 0, 0, bufferSize, atrBuffer) < bufferSize)
      return false;
   
   //--- Copy price data
   if(CopyHigh(_Symbol, ExecutionTF, 0, bufferSize, highBuffer) < bufferSize ||
      CopyLow(_Symbol, ExecutionTF, 0, bufferSize, lowBuffer) < bufferSize ||
      CopyClose(_Symbol, ExecutionTF, 0, bufferSize, closeBuffer) < bufferSize ||
      CopyOpen(_Symbol, ExecutionTF, 0, bufferSize, openBuffer) < bufferSize)
      return false;
   
   //--- Copy Lower TF price data
   if(CopyHigh(_Symbol, LowerTF, 0, bufferSize, lowerHighBuffer) < bufferSize ||
      CopyLow(_Symbol, LowerTF, 0, bufferSize, lowerLowBuffer) < bufferSize ||
      CopyClose(_Symbol, LowerTF, 0, bufferSize, lowerCloseBuffer) < bufferSize ||
      CopyOpen(_Symbol, LowerTF, 0, bufferSize, lowerOpenBuffer) < bufferSize)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Count current trades for this EA on chart symbol                 |
//+------------------------------------------------------------------+
int CountCurrentTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == MagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count current lower TF trades on chart symbol                   |
//+------------------------------------------------------------------+
int CountCurrentLowerTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == LowerTFMagicNumber)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if step index trading is enabled                           |
//+------------------------------------------------------------------+
bool CanTradeStepIndex()
{
   return (TradeStepIndex || TradeStepIndex200 || TradeStepIndex300 || TradeStepIndex400 || TradeStepIndex500);
}

//+------------------------------------------------------------------+
//| Check ALL enabled step index signals (trades each independently) |
//+------------------------------------------------------------------+
void CheckAllStepIndexSignals()
{
   //--- Trade STEPINDEX (600)
   if(TradeStepIndex)
   {
      CheckAndTradeStepIndex("STEPINDEX", StepIndexMagicNumber);
   }
   
   //--- Trade STEPINDEX200
   if(TradeStepIndex200)
   {
      CheckAndTradeStepIndex("STEPINDEX200", StepIndex200MagicNumber);
   }
   
   //--- Trade STEPINDEX300
   if(TradeStepIndex300)
   {
      CheckAndTradeStepIndex("STEPINDEX300", StepIndex300MagicNumber);
   }
   
   //--- Trade STEPINDEX400
   if(TradeStepIndex400)
   {
      CheckAndTradeStepIndex("STEPINDEX400", StepIndex400MagicNumber);
   }
   
   //--- Trade STEPINDEX500
   if(TradeStepIndex500)
   {
      CheckAndTradeStepIndex("STEPINDEX500", StepIndex500MagicNumber);
   }
}

//+------------------------------------------------------------------+
//| Check and trade a single step index symbol                       |
//+------------------------------------------------------------------+
void CheckAndTradeStepIndex(string stepSymbol, ulong stepMagic)
{
   //--- Check if this symbol is available for trading
   if(!SymbolSelect(stepSymbol, true))
   {
      Print("Warning: ", stepSymbol, " not available or cannot be selected");
      return;
   }
   
   //--- Check if we already have an OPEN position for this step index
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == stepSymbol && position.Magic() == stepMagic)
         {
            //--- Position already exists for this symbol, don't trade again
            return;
         }
      }
   }
   
   //--- No position exists, open one
   double ask = SymbolInfoDouble(stepSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(stepSymbol, SYMBOL_BID);
   
   if(ask <= 0 || bid <= 0)
   {
      Print("Error: Invalid price for ", stepSymbol);
      return;
   }
   
   string comment = "Step Index " + stepSymbol + " Auto Buy";
   
   //--- Execute trade with proper magic number
   trade.SetExpertMagicNumber(stepMagic);
   bool success = trade.Buy(LotSize, stepSymbol, ask, 0, 0, comment);
   
   if(success)
   {
      Print("✓ ", stepSymbol, " Buy executed successfully. Ticket: ", trade.ResultOrder());
   }
   else
   {
      Print("✗ ", stepSymbol, " Buy failed. Error: ", trade.ResultComment(), " Retcode: ", trade.ResultRetcode());
   }
   
   //--- Reset to chart magic number
   trade.SetExpertMagicNumber(MagicNumber);
}

//+------------------------------------------------------------------+
//| Calculate basket profit (ALL positions)                          |
//+------------------------------------------------------------------+
void CalculateBasketProfit()
{
   basketProfit = 0.0;
   int positionCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         //--- Include chart symbol trades (both Main TF and Lower TF)
         if(position.Symbol() == _Symbol && 
            (position.Magic() == MagicNumber || position.Magic() == LowerTFMagicNumber))
         {
            basketProfit += position.Profit();
            positionCount++;
            Print("Chart Position: ", position.Ticket(), " | Symbol: ", position.Symbol(), 
                  " | Profit: ", position.Profit(), " | Magic: ", position.Magic());
         }
         
         //--- Include STEPINDEX trades
         if(position.Magic() == StepIndexMagicNumber && position.Symbol() == "STEPINDEX")
         {
            basketProfit += position.Profit();
            positionCount++;
            Print("STEPINDEX Position: ", position.Ticket(), " | Profit: ", position.Profit());
         }
         
         //--- Include STEPINDEX200 trades
         if(position.Magic() == StepIndex200MagicNumber && position.Symbol() == "STEPINDEX200")
         {
            basketProfit += position.Profit();
            positionCount++;
            Print("STEPINDEX200 Position: ", position.Ticket(), " | Profit: ", position.Profit());
         }
         
         //--- Include STEPINDEX300 trades
         if(position.Magic() == StepIndex300MagicNumber && position.Symbol() == "STEPINDEX300")
         {
            basketProfit += position.Profit();
            positionCount++;
            Print("STEPINDEX300 Position: ", position.Ticket(), " | Profit: ", position.Profit());
         }
         
         //--- Include STEPINDEX400 trades
         if(position.Magic() == StepIndex400MagicNumber && position.Symbol() == "STEPINDEX400")
         {
            basketProfit += position.Profit();
            positionCount++;
            Print("STEPINDEX400 Position: ", position.Ticket(), " | Profit: ", position.Profit());
         }
         
         //--- Include STEPINDEX500 trades
         if(position.Magic() == StepIndex500MagicNumber && position.Symbol() == "STEPINDEX500")
         {
            basketProfit += position.Profit();
            positionCount++;
            Print("STEPINDEX500 Position: ", position.Ticket(), " | Profit: ", position.Profit());
         }
      }
   }
   
   Print("=== Basket Profit Summary === Total Profit: ", basketProfit, " | Positions: ", positionCount);
}

//+------------------------------------------------------------------+
//| Check basket profit target                                     |
//+------------------------------------------------------------------+
bool CheckBasketProfitTarget()
{
   if(!EnableBasketProfit) 
      return false;
   
   CalculateBasketProfit();
   
   if(basketProfit >= BasketProfitTarget)
   {
      Print(">>> BASKET PROFIT TARGET REACHED! Profit: ", basketProfit, " >= Target: ", BasketProfitTarget);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Close all basket trades (chart + step index)                    |
//+------------------------------------------------------------------+
void CloseAllBasketTrades()
{
   int closedCount = 0;
   
   //--- Close chart symbol positions first
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && 
            (position.Magic() == MagicNumber || position.Magic() == LowerTFMagicNumber))
         {
            bool result = trade.PositionClose(position.Ticket());
            if(result)
            {
               Print("Closed chart position: ", position.Ticket(), " | Profit: ", position.Profit());
               closedCount++;
            }
            else
            {
               Print("Failed to close chart position: ", position.Ticket());
            }
         }
      }
   }
   
   //--- Close all step index positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if((position.Magic() == StepIndexMagicNumber && position.Symbol() == "STEPINDEX") ||
            (position.Magic() == StepIndex200MagicNumber && position.Symbol() == "STEPINDEX200") ||
            (position.Magic() == StepIndex300MagicNumber && position.Symbol() == "STEPINDEX300") ||
            (position.Magic() == StepIndex400MagicNumber && position.Symbol() == "STEPINDEX400") ||
            (position.Magic() == StepIndex500MagicNumber && position.Symbol() == "STEPINDEX500"))
         {
            bool result = trade.PositionClose(position.Ticket());
            if(result)
            {
               Print("Closed step index position: ", position.Symbol(), " | Ticket: ", position.Ticket(), " | Profit: ", position.Profit());
               closedCount++;
            }
            else
            {
               Print("Failed to close step index position: ", position.Symbol());
            }
         }
      }
   }
   
   Print("Closed total ", closedCount, " positions. Basket profit target: ", BasketProfitTarget);
}

//+------------------------------------------------------------------+
//| Close trades by magic number and position type                  |
//+------------------------------------------------------------------+
void CloseTradesByMagicAndType(ulong magicNumber, ENUM_POSITION_TYPE positionType)
{
   int closedCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == magicNumber && position.PositionType() == positionType)
         {
            bool result = trade.PositionClose(position.Ticket());
            if(result)
            {
               Print("Closed position: ", position.Ticket(), " | Type: ", EnumToString(positionType));
               closedCount++;
            }
            else
            {
               Print("Failed to close position: ", position.Ticket(), " | Error: ", trade.ResultRetcode());
            }
         }
      }
   }
   
   if(closedCount > 0)
      Print("Closed ", closedCount, " positions with Magic: ", magicNumber, " Type: ", EnumToString(positionType));
}

//+------------------------------------------------------------------+
//| Check for trade signals on chart symbol                          |
//+------------------------------------------------------------------+
void CheckTradeSignals()
{
   //--- Use previous bar for crossover detection
   double closePrice = closeBuffer[1];
   double smaCloseValue = smaCloseBuffer[1];
   
   //--- Detect crossover
   bool currentAboveSMA = (closePrice > smaCloseValue);
   
   //--- Update higher TF trend direction
   if(currentAboveSMA)
      higherTF_Trend = 1; // Uptrend
   else
      higherTF_Trend = -1; // Downtrend
   
   //--- Exit trades on opposite cross FIRST
   if(lastAboveSMA && !currentAboveSMA) // Bearish cross
   {
      Print("Bearish crossover detected - closing BUY positions");
      CloseTradesByMagicAndType(MagicNumber, POSITION_TYPE_BUY);
   }
   
   if(!lastAboveSMA && currentAboveSMA) // Bullish cross
   {
      Print("Bullish crossover detected - closing SELL positions");
      CloseTradesByMagicAndType(MagicNumber, POSITION_TYPE_SELL);
   }
   
   //--- Small delay to ensure trades are closed before opening new ones
   Sleep(100);
   
   //--- Buy signal: Price crosses above SMA close
   if(!lastAboveSMA && currentAboveSMA)
   {
      Print("Buy crossover detected - opening ", NumberOfTradesPerSignal, " trades");
      if(CheckBuyConditions())
      {
         ExecuteMultipleTrades(ORDER_TYPE_BUY, MagicNumber);
      }
   }
   
   //--- Sell signal: Price crosses below SMA close
   if(lastAboveSMA && !currentAboveSMA)
   {
      Print("Sell crossover detected - opening ", NumberOfTradesPerSignal, " trades");
      if(CheckSellConditions())
      {
         ExecuteMultipleTrades(ORDER_TYPE_SELL, MagicNumber);
      }
   }
   
   lastAboveSMA = currentAboveSMA;
}

//+------------------------------------------------------------------+
//| Check lower timeframe signals                                    |
//+------------------------------------------------------------------+
void CheckLowerTFSignals()
{
   double lowerClosePrice = lowerCloseBuffer[1];
   double lowerSmaCloseValue = lowerSmaCloseBuffer[1];
   
   //--- Detect crossover
   bool currentLowerAboveSMA = (lowerClosePrice > lowerSmaCloseValue);
   
   //--- Exit trades on opposite cross FIRST (Lower TF exits on Lower TF crosses)
   if(lastLowerAboveSMA && !currentLowerAboveSMA) // Bearish cross
   {
      Print("Lower TF Bearish crossover - closing BUY positions");
      CloseTradesByMagicAndType(LowerTFMagicNumber, POSITION_TYPE_BUY);
   }
   
   if(!lastLowerAboveSMA && currentLowerAboveSMA) // Bullish cross
   {
      Print("Lower TF Bullish crossover - closing SELL positions");
      CloseTradesByMagicAndType(LowerTFMagicNumber, POSITION_TYPE_SELL);
   }
   
   //--- Delay to ensure trades are closed before opening new ones
   Sleep(500);
   
   //--- Buy signal: Price crosses above SMA close (only if higher TF is uptrend)
   if(!lastLowerAboveSMA && currentLowerAboveSMA && higherTF_Trend == 1)
   {
      Print("Lower TF Buy crossover detected (Trend confirmed uptrend)");
      if(CheckLowerBuyConditions())
      {
         ExecuteMultipleTrades(ORDER_TYPE_BUY, LowerTFMagicNumber);
      }
   }
   
   //--- Sell signal: Price crosses below SMA close (only if higher TF is downtrend)
   if(lastLowerAboveSMA && !currentLowerAboveSMA && higherTF_Trend == -1)
   {
      Print("Lower TF Sell crossover detected (Trend confirmed downtrend)");
      if(CheckLowerSellConditions())
      {
         ExecuteMultipleTrades(ORDER_TYPE_SELL, LowerTFMagicNumber);
      }
   }
   
   lastLowerAboveSMA = currentLowerAboveSMA;
}

//+------------------------------------------------------------------+
//| Check buy conditions (filters)                                   |
//+------------------------------------------------------------------+
bool CheckBuyConditions()
{
   //--- Trend filter check
   if(UseTrendFilter)
   {
      if(closeBuffer[1] <= trendSMABuffer[1])
      {
         Print("Buy blocked: Price below trend SMA");
         return false;
      }
   }
   
   //--- AO divergence filter check
   if(EnableAODivergence)
   {
      if(DetectAODivergence(true)) // Bearish divergence blocks buy
      {
         Print("Buy blocked: Bearish AO divergence detected");
         return false;
      }
   }
   
   //--- ATR volatility filter check
   if(EnableATRFilter)
   {
      if(!DetectATRVolatility())
      {
         Print("Buy blocked: ATR volatility filter");
         return false;
      }
   }
   
   //--- CHoCH/BOS sniper confirmation
   if(EnableSniperMode)
   {
      if(!DetectCHOCHBOS(true))
      {
         Print("Buy blocked: No CHoCH/BOS confirmation");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check lower TF buy conditions                                    |
//+------------------------------------------------------------------+
bool CheckLowerBuyConditions()
{
   return true;
}

//+------------------------------------------------------------------+
//| Check sell conditions (filters)                                  |
//+------------------------------------------------------------------+
bool CheckSellConditions()
{
   //--- Trend filter check
   if(UseTrendFilter)
   {
      if(closeBuffer[1] >= trendSMABuffer[1])
      {
         Print("Sell blocked: Price above trend SMA");
         return false;
      }
   }
   
   //--- AO divergence filter check
   if(EnableAODivergence)
   {
      if(DetectAODivergence(false)) // Bullish divergence blocks sell
      {
         Print("Sell blocked: Bullish AO divergence detected");
         return false;
      }
   }
   
   //--- ATR volatility filter check
   if(EnableATRFilter)
   {
      if(!DetectATRVolatility())
      {
         Print("Sell blocked: ATR volatility filter");
         return false;
      }
   }
   
   //--- CHoCH/BOS sniper confirmation
   if(EnableSniperMode)
   {
      if(!DetectCHOCHBOS(false))
      {
         Print("Sell blocked: No CHoCH/BOS confirmation");
         return false;
      }
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Check lower TF sell conditions                                  |
//+------------------------------------------------------------------+
bool CheckLowerSellConditions()
{
   return true;
}

//+------------------------------------------------------------------+
//| Execute multiple trades on chart symbol                          |
//+------------------------------------------------------------------+
void ExecuteMultipleTrades(ENUM_ORDER_TYPE orderType, ulong magicNum)
{
   double sl = 0;
   double price = 0;
   string comment = "";
   
   //--- Determine price and SL based on order type and magic number
   if(orderType == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      if(magicNum == MagicNumber)
      {
         sl = smaLowBuffer[1]; // SMA Low for main TF
         comment = "SMA Crossover Buy";
      }
      else
      {
         sl = lowerSmaLowBuffer[1]; // Lower TF SMA Low
         comment = "Lower TF SMA Buy";
      }
   }
   else // SELL
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      if(magicNum == MagicNumber)
      {
         sl = smaHighBuffer[1]; // SMA High for main TF
         comment = "SMA Crossover Sell";
      }
      else
      {
         sl = lowerSmaHighBuffer[1]; // Lower TF SMA High
         comment = "Lower TF SMA Sell";
      }
   }
   
   //--- Execute multiple trades
   for(int i = 1; i <= NumberOfTradesPerSignal; i++)
   {
      bool success = false;
      trade.SetExpertMagicNumber(magicNum);
      
      if(orderType == ORDER_TYPE_BUY)
         success = trade.Buy(LotSize, _Symbol, price, sl, 0, comment + " #" + IntegerToString(i));
      else
         success = trade.Sell(LotSize, _Symbol, price, sl, 0, comment + " #" + IntegerToString(i));
      
      if(success)
      {
         Print("✓ Trade ", i, "/", NumberOfTradesPerSignal, " executed - Ticket: ", trade.ResultOrder());
      }
      else
      {
         Print("✗ Trade ", i, "/", NumberOfTradesPerSignal, " failed - Error: ", trade.ResultComment());
      }
      
      Sleep(100);
   }
   
   trade.SetExpertMagicNumber(MagicNumber);
}

//+------------------------------------------------------------------+
//| Detect AO divergence                                             |
//+------------------------------------------------------------------+
bool DetectAODivergence(bool isBuySignal)
{
   UpdateMarketStructure();
   
   //--- Look for bullish divergence (blocks sell)
   for(int i = 0; i < ArraySize(swingLows) - 1; i++)
   {
      if(swingLows[i] == -1 || swingLows[i+1] == -1)
         continue;
      
      double priceLow1 = lowBuffer[swingLows[i]];
      double priceLow2 = lowBuffer[swingLows[i+1]];
      
      int aoLow1 = FindAOLowNearIndex(swingLows[i], 3);
      int aoLow2 = FindAOLowNearIndex(swingLows[i+1], 3);
      
      if(aoLow1 == -1 || aoLow2 == -1)
         continue;
      
      double aoValue1 = aoBuffer[aoLow1];
      double aoValue2 = aoBuffer[aoLow2];
      
      //--- Regular bullish divergence: Price LL, AO HL
      if(priceLow1 < priceLow2 && aoValue1 > aoValue2)
      {
         if(!isBuySignal) return true; // Blocks sell
      }
      
      //--- Hidden bullish divergence: Price HL, AO LL
      if(EnableHiddenDivergence && priceLow1 > priceLow2 && aoValue1 < aoValue2)
      {
         if(!isBuySignal) return true; // Blocks sell
      }
   }
   
   //--- Look for bearish divergence (blocks buy)
   for(int i = 0; i < ArraySize(swingHighs) - 1; i++)
   {
      if(swingHighs[i] == -1 || swingHighs[i+1] == -1)
         continue;
      
      double priceHigh1 = highBuffer[swingHighs[i]];
      double priceHigh2 = highBuffer[swingHighs[i+1]];
      
      int aoHigh1 = FindAOHighNearIndex(swingHighs[i], 3);
      int aoHigh2 = FindAOHighNearIndex(swingHighs[i+1], 3);
      
      if(aoHigh1 == -1 || aoHigh2 == -1)
         continue;
      
      double aoValue1 = aoBuffer[aoHigh1];
      double aoValue2 = aoBuffer[aoHigh2];
      
      //--- Regular bearish divergence: Price HH, AO LH
      if(priceHigh1 > priceHigh2 && aoValue1 < aoValue2)
      {
         if(isBuySignal) return true; // Blocks buy
      }
      
      //--- Hidden bearish divergence: Price LH, AO HH
      if(EnableHiddenDivergence && priceHigh1 < priceHigh2 && aoValue1 > aoValue2)
      {
         if(isBuySignal) return true; // Blocks buy
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect ATR volatility                                            |
//+------------------------------------------------------------------+
bool DetectATRVolatility()
{
   double currentATR = atrBuffer[0];
   
   //--- Minimum threshold check
   if(currentATR < ATRMinThreshold)
      return false;
   
   //--- Relative ATR mode
   if(UseRelativeATR)
   {
      double atrAverage = 0;
      for(int i = 1; i <= ATRRelativeLookback; i++)
      {
         atrAverage += atrBuffer[i];
      }
      atrAverage /= ATRRelativeLookback;
      
      if(currentATR <= atrAverage)
         return false;
   }
   
   //--- Range detection mode
   if(EnableRangeDetection)
   {
      bool isContracting = true;
      for(int i = 0; i < RangeContractionBars; i++)
      {
         if(currentATR >= atrBuffer[i+1])
         {
            isContracting = false;
            break;
         }
      }
      
      if(isContracting)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Detect CHoCH/BOS confirmation                                   |
//+------------------------------------------------------------------+
bool DetectCHOCHBOS(bool isBuySignal)
{
   UpdateMarketStructure();
   
   if(isBuySignal)
   {
      //--- Look for bullish CHoCH or BOS
      for(int i = 0; i < ArraySize(swingHighs) - 1; i++)
      {
         if(swingHighs[i] == -1 || swingHighs[i+1] == -1)
            continue;
         
         double recentHigh = highBuffer[swingHighs[i]];
         double previousHigh = highBuffer[swingHighs[i+1]];
         
         //--- Bullish BOS: Break above previous swing high
         if(recentHigh > previousHigh && closeBuffer[0] > recentHigh)
         {
            if(EnableRetestEntry)
               return DetectRetest(recentHigh, true);
            else
               return true;
         }
         
         //--- Bullish CHoCH: Break above lower high (reversal)
         if(recentHigh < previousHigh && closeBuffer[0] > recentHigh)
         {
            if(EnableRetestEntry)
               return DetectRetest(recentHigh, true);
            else
               return true;
         }
      }
   }
   else // Sell signal
   {
      //--- Look for bearish CHoCH or BOS
      for(int i = 0; i < ArraySize(swingLows) - 1; i++)
      {
         if(swingLows[i] == -1 || swingLows[i+1] == -1)
            continue;
         
         double recentLow = lowBuffer[swingLows[i]];
         double previousLow = lowBuffer[swingLows[i+1]];
         
         //--- Bearish BOS: Break below previous swing low
         if(recentLow < previousLow && closeBuffer[0] < recentLow)
         {
            if(EnableRetestEntry)
               return DetectRetest(recentLow, false);
            else
               return true;
         }
         
         //--- Bearish CHoCH: Break below higher low (reversal)
         if(recentLow > previousLow && closeBuffer[0] < recentLow)
         {
            if(EnableRetestEntry)
               return DetectRetest(recentLow, false);
            else
               return true;
         }
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Detect retest after BOS/CHoCH                                   |
//+------------------------------------------------------------------+
bool DetectRetest(double brokenLevel, bool isBuySignal)
{
   double tolerance = atrBuffer[0] * 0.5;
   
   if(isBuySignal)
   {
      if(lowBuffer[0] <= brokenLevel + tolerance && 
         lowBuffer[0] >= brokenLevel - tolerance &&
         closeBuffer[0] > brokenLevel)
         return true;
   }
   else
   {
      if(highBuffer[0] >= brokenLevel - tolerance && 
         highBuffer[0] <= brokenLevel + tolerance &&
         closeBuffer[0] < brokenLevel)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update market structure (swing highs/lows)                       |
//+------------------------------------------------------------------+
void UpdateMarketStructure()
{
   ArrayInitialize(swingHighs, -1);
   ArrayInitialize(swingLows, -1);
   
   int highSwingCount = 0;
   int lowSwingCount = 0;
   
   //--- Find swing highs
   for(int i = 5; i < StructureLookback && highSwingCount < StructureLookback; i++)
   {
      bool isValidHigh = true;
      
      for(int j = 1; j <= 5; j++)
      {
         if(i >= j && highBuffer[i] <= highBuffer[i-j])
         {
            isValidHigh = false;
            break;
         }
      }
      
      if(isValidHigh)
      {
         for(int j = 1; j <= 3; j++)
         {
            if(i + j < ArraySize(highBuffer) && highBuffer[i] <= highBuffer[i+j])
            {
               isValidHigh = false;
               break;
            }
         }
      }
      
      if(isValidHigh)
      {
         swingHighs[highSwingCount] = i;
         swingHighPrices[highSwingCount] = highBuffer[i];
         highSwingCount++;
      }
   }
   
   //--- Find swing lows
   for(int i = 5; i < StructureLookback && lowSwingCount < StructureLookback; i++)
   {
      bool isValidLow = true;
      
      for(int j = 1; j <= 5; j++)
      {
         if(i >= j && lowBuffer[i] >= lowBuffer[i-j])
         {
            isValidLow = false;
            break;
         }
      }
      
      if(isValidLow)
      {
         for(int j = 1; j <= 3; j++)
         {
            if(i + j < ArraySize(lowBuffer) && lowBuffer[i] >= lowBuffer[i+j])
            {
               isValidLow = false;
               break;
            }
         }
      }
      
      if(isValidLow)
      {
         swingLows[lowSwingCount] = i;
         swingLowPrices[lowSwingCount] = lowBuffer[i];
         lowSwingCount++;
      }
   }
}

//+------------------------------------------------------------------+
//| Find AO low near price index                                     |
//+------------------------------------------------------------------+
int FindAOLowNearIndex(int priceIndex, int tolerance)
{
   int start = MathMax(0, priceIndex - tolerance);
   int end = MathMin(ArraySize(aoBuffer) - 1, priceIndex + tolerance);
   
   double lowestAO = aoBuffer[start];
   int lowestIndex = start;
   
   for(int i = start; i <= end; i++)
   {
      if(aoBuffer[i] < lowestAO)
      {
         lowestAO = aoBuffer[i];
         lowestIndex = i;
      }
   }
   
   return lowestIndex;
}

//+------------------------------------------------------------------+
//| Find AO high near price index                                    |
//+------------------------------------------------------------------+
int FindAOHighNearIndex(int priceIndex, int tolerance)
{
   int start = MathMax(0, priceIndex - tolerance);
   int end = MathMin(ArraySize(aoBuffer) - 1, priceIndex + tolerance);
   
   double highestAO = aoBuffer[start];
   int highestIndex = start;
   
   for(int i = start; i <= end; i++)
   {
      if(aoBuffer[i] > highestAO)
      {
         highestAO = aoBuffer[i];
         highestIndex = i;
      }
   }
   
   return highestIndex;
}

//+------------------------------------------------------------------+
//| Trail stop loss for all positions                                |
//+------------------------------------------------------------------+
void TrailSL()
{
   //--- Trail main TF trades
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == MagicNumber)
         {
            double currentSL = position.StopLoss();
            double newSL = 0;
            
            if(position.PositionType() == POSITION_TYPE_BUY)
            {
               newSL = smaLowBuffer[0];
               if(newSL > currentSL || currentSL == 0)
               {
                  trade.PositionModify(position.Ticket(), newSL, position.TakeProfit());
                  Print("Buy SL trailed to: ", newSL);
               }
            }
            else if(position.PositionType() == POSITION_TYPE_SELL)
            {
               newSL = smaHighBuffer[0];
               if(newSL < currentSL || currentSL == 0)
               {
                  trade.PositionModify(position.Ticket(), newSL, position.TakeProfit());
                  Print("Sell SL trailed to: ", newSL);
               }
            }
         }
      }
   }
   
   //--- Trail lower TF trades
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(position.SelectByIndex(i))
      {
         if(position.Symbol() == _Symbol && position.Magic() == LowerTFMagicNumber)
         {
            double currentSL = position.StopLoss();
            double newSL = 0;
            
            if(position.PositionType() == POSITION_TYPE_BUY)
            {
               newSL = lowerSmaLowBuffer[0];
               if(newSL > currentSL || currentSL == 0)
               {
                  trade.PositionModify(position.Ticket(), newSL, position.TakeProfit());
                  Print("Lower TF Buy SL trailed to: ", newSL);
               }
            }
            else if(position.PositionType() == POSITION_TYPE_SELL)
            {
               newSL = lowerSmaHighBuffer[0];
               if(newSL < currentSL || currentSL == 0)
               {
                  trade.PositionModify(position.Ticket(), newSL, position.TakeProfit());
                  Print("Lower TF Sell SL trailed to: ", newSL);
               }
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
