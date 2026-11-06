
//+------------------------------------------------------------------+
//| DTS STRATEGIC AI EA v1.0                                         |
//| Demaks Trading Suite                                             |
//| Platform: MetaTrader 5                                           |
//| Markets: NASDAQ and XAUUSD                                       |
//| Phase 1: Quantitative Signal Engine                              |
//| Execution: DISABLED                                              |
//+------------------------------------------------------------------+

#property strict
#property version "1.00"
#property description "DTS Strategic AI EA - Quantitative Signal Engine"

input string InpSymbols = "USTEC,XAUUSD";
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;

input double InpRiskPercent = 0.5;

input int InpFastEMA = 20;
input int InpSlowEMA = 50;
input int InpRSIPeriod = 14;
input int InpATRPeriod = 14;

input double InpBullishRSI = 55.0;
input double InpBearishRSI = 45.0;

input double InpStopATRMultiplier = 2.0;
input int InpMaxSpreadPoints = 1000;

input bool InpEnableExecution = false;

struct SymbolEngine
{
   string symbol;
   int fastEMA;
   int slowEMA;
   int rsi;
   int atr;
   datetime lastBar;
};

SymbolEngine engines[];

int OnInit()
{
   string symbols[];
   int count = StringSplit(InpSymbols, ',', symbols);

   if(count <= 0)
      return INIT_FAILED;

   ArrayResize(engines, count);

   for(int i = 0; i < count; i++)
   {
      StringTrimLeft(symbols[i]);
      StringTrimRight(symbols[i]);

      engines[i].symbol = symbols[i];
      engines[i].lastBar = 0;

      if(!SymbolSelect(symbols[i], true))
      {
         Print("Cannot select symbol: ", symbols[i]);
         return INIT_FAILED;
      }

      engines[i].fastEMA = iMA(
         symbols[i], InpTimeframe, InpFastEMA,
         0, MODE_EMA, PRICE_CLOSE);

      engines[i].slowEMA = iMA(
         symbols[i], InpTimeframe, InpSlowEMA,
         0, MODE_EMA, PRICE_CLOSE);

      engines[i].rsi = iRSI(
         symbols[i], InpTimeframe,
         InpRSIPeriod, PRICE_CLOSE);

      engines[i].atr = iATR(
         symbols[i], InpTimeframe, InpATRPeriod);

      if(engines[i].fastEMA == INVALID_HANDLE ||
         engines[i].slowEMA == INVALID_HANDLE ||
         engines[i].rsi == INVALID_HANDLE ||
         engines[i].atr == INVALID_HANDLE)
      {
         Print("Indicator initialization failed: ",
               symbols[i]);
         return INIT_FAILED;
      }
   }

   Print("DTS Strategic AI EA initialized.");
   Print("Signal-only mode active. Execution disabled.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   for(int i = 0; i < ArraySize(engines); i++)
   {
      IndicatorRelease(engines[i].fastEMA);
      IndicatorRelease(engines[i].slowEMA);
      IndicatorRelease(engines[i].rsi);
      IndicatorRelease(engines[i].atr);
   }

   Comment("");
   Print("DTS Strategic AI EA stopped.");
}

bool ReadIndicator(
   int handle,
   double &value)
{
   double buffer[];

   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(handle, 0, 1, 1, buffer) != 1)
      return false;

   value = buffer[0];
   return true;
}

string GenerateSignal(int index)
{
   double fast, slow, rsi, atr;

   if(!ReadIndicator(engines[index].fastEMA, fast))
      return "WAITING FOR DATA";

   if(!ReadIndicator(engines[index].slowEMA, slow))
      return "WAITING FOR DATA";

   if(!ReadIndicator(engines[index].rsi, rsi))
      return "WAITING FOR DATA";

   if(!ReadIndicator(engines[index].atr, atr))
      return "WAITING FOR DATA";

   if(atr <= 0)
      return "INVALID ATR";

   if(fast > slow && rsi >= InpBullishRSI)
      return "BULLISH";

   if(fast < slow && rsi <= InpBearishRSI)
      return "BEARISH";

   return "NEUTRAL";
}

void OnTick()
{
   string dashboard = "DTS STRATEGIC AI EA v1.0\n";
   dashboard += "PHASE 1 - SIGNAL ENGINE\n";
   dashboard += "EXECUTION: DISABLED\n\n";

   for(int i = 0; i < ArraySize(engines); i++)
   {
      string signal = GenerateSignal(i);

      dashboard += engines[i].symbol + " | ";
      dashboard += signal + "\n";
   }

   Comment(dashboard);
}
