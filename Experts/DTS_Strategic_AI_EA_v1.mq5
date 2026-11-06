
#property strict
#property version "1.30"
#property description "DTS Strategic AI EA - Multi-Symbol Quant Engine"

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
   string signal;
   string reason;
   int quality;
   double spread;
   double stopDistance;
   double volume;
};

SymbolEngine engines[];

int OnInit()
{
   if(InpRiskPercent <= 0 ||
      InpRiskPercent > 0.5 ||
      InpMaxSpreadPoints <= 0 ||
      InpFastEMA <= 0 ||
      InpSlowEMA <= InpFastEMA)
      return INIT_PARAMETERS_INCORRECT;

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
      engines[i].signal = "INITIALIZING";
      engines[i].reason = "Waiting for data";
      engines[i].quality = 0;

      if(!SymbolSelect(symbols[i], true))
      {
         Print("Cannot select symbol: ", symbols[i]);
         return INIT_FAILED;
      }

      engines[i].fastEMA = iMA(
         symbols[i], InpTimeframe,
         InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);

      engines[i].slowEMA = iMA(
         symbols[i], InpTimeframe,
         InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

      engines[i].rsi = iRSI(
         symbols[i], InpTimeframe,
         InpRSIPeriod, PRICE_CLOSE);

      engines[i].atr = iATR(
         symbols[i], InpTimeframe,
         InpATRPeriod);

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

   Print("DTS v1.30 multi-symbol engine initialized.");
   Print("Automatic execution remains disabled.");

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
}

bool ReadIndicator(int handle, double &value)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(handle, 0, 1, 1, buffer) != 1)
      return false;

   value = buffer[0];
   return true;
}

double GetSpreadPoints(string symbol)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(ask <= 0 || bid <= 0 || point <= 0)
      return -1.0;

   return (ask - bid) / point;
}

double CalculateRiskMoney()
{
   return AccountInfoDouble(ACCOUNT_EQUITY)
          * InpRiskPercent / 100.0;
}

double CalculateStopDistance(int index)
{
   double atr;

   if(!ReadIndicator(engines[index].atr, atr))
      return 0.0;

   return atr * InpStopATRMultiplier;
}

double CalculateVolume(string symbol, double stopDistance)
{
   if(stopDistance <= 0)
      return 0.0;

   double tickSize =
      SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   double tickValue =
      SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);

   double minVolume =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);

   double maxVolume =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   double volumeStep =
      SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   if(tickSize <= 0 || tickValue <= 0 ||
      volumeStep <= 0)
      return 0.0;

   double lossPerLot =
      stopDistance / tickSize * tickValue;

   if(lossPerLot <= 0)
      return 0.0;

   double rawVolume = CalculateRiskMoney() / lossPerLot;

   double volume =
      MathFloor(rawVolume / volumeStep) * volumeStep;

   if(volume < minVolume)
      return 0.0;

   if(volume > maxVolume)
      volume = MathFloor(maxVolume / volumeStep)
               * volumeStep;

   return NormalizeDouble(volume, 8);
}

bool UpdateSymbol(int index)
{
   string symbol = engines[index].symbol;

   datetime currentBar =
      iTime(symbol, InpTimeframe, 0);

   if(currentBar <= 0)
      return false;

   if(currentBar == engines[index].lastBar)
      return true;

   engines[index].lastBar = currentBar;

   double spread = GetSpreadPoints(symbol);
   engines[index].spread = spread;

   if(spread < 0)
   {
      engines[index].signal = "DATA ERROR";
      engines[index].reason = "Spread unavailable";
      return false;
   }

   if(spread > InpMaxSpreadPoints)
   {
      engines[index].signal = "REJECTED";
      engines[index].reason = "High spread";
      engines[index].quality = 0;
      return true;
   }

   double fast, slow, rsi, atr;

   if(!ReadIndicator(engines[index].fastEMA, fast) ||
      !ReadIndicator(engines[index].slowEMA, slow) ||
      !ReadIndicator(engines[index].rsi, rsi) ||
      !ReadIndicator(engines[index].atr, atr))
   {
      engines[index].signal = "WAITING";
      engines[index].reason = "Indicator data unavailable";
      engines[index].quality = 0;
      return false;
   }

   if(atr <= 0)
   {
      engines[index].signal = "WAITING";
      engines[index].reason = "Invalid ATR";
      engines[index].quality = 0;
      return false;
   }

   engines[index].quality = 1;

   if(fast > slow && rsi >= InpBullishRSI)
   {
      engines[index].signal = "BULLISH";
      engines[index].reason = "EMA and RSI confirmed";
      engines[index].quality = 3;
   }
   else if(fast < slow && rsi <= InpBearishRSI)
   {
      engines[index].signal = "BEARISH";
      engines[index].reason = "EMA and RSI confirmed";
      engines[index].quality = 3;
   }
   else
   {
      engines[index].signal = "NEUTRAL";
      engines[index].reason = "Conditions not aligned";
   }

   engines[index].stopDistance =
      atr * InpStopATRMultiplier;

   engines[index].volume =
      CalculateVolume(symbol, engines[index].stopDistance);

   return true;
}

void OnTick()
{
   string dashboard = "DTS STRATEGIC AI EA v1.30\n";
   dashboard += "MULTI-SYMBOL MONITOR\n";
   dashboard += "EXECUTION: DISABLED\n";
   dashboard += "RISK SETTING: 0.5%\n\n";

   for(int i = 0; i < ArraySize(engines); i++)
   {
      UpdateSymbol(i);

      dashboard += engines[i].symbol + "\n";
      dashboard += "Signal: " + engines[i].signal + "\n";
      dashboard += "Quality: " +
         IntegerToString(engines[i].quality) + "/3\n";
      dashboard += "Spread: " +
         DoubleToString(engines[i].spread, 1) + "\n";
      dashboard += "Reason: " + engines[i].reason + "\n";
      dashboard += "Stop distance: " +
         DoubleToString(engines[i].stopDistance, 5) + "\n";
      dashboard += "Estimated volume: " +
         DoubleToString(engines[i].volume, 2) + "\n\n";
   }

   Comment(dashboard);
}
