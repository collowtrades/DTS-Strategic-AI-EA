
#property strict
#property version "1.10"
#property description "DTS Strategic AI EA - Signal and Risk Engine"

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

input bool InpEnableExecution = false;

struct SymbolEngine
{
   string symbol;
   int fastEMA;
   int slowEMA;
   int rsi;
   int atr;
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

      if(!SymbolSelect(symbols[i], true))
         return INIT_FAILED;

      engines[i].fastEMA = iMA(symbols[i], InpTimeframe,
         InpFastEMA, 0, MODE_EMA, PRICE_CLOSE);

      engines[i].slowEMA = iMA(symbols[i], InpTimeframe,
         InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE);

      engines[i].rsi = iRSI(symbols[i], InpTimeframe,
         InpRSIPeriod, PRICE_CLOSE);

      engines[i].atr = iATR(symbols[i], InpTimeframe,
         InpATRPeriod);

      if(engines[i].fastEMA == INVALID_HANDLE ||
         engines[i].slowEMA == INVALID_HANDLE ||
         engines[i].rsi == INVALID_HANDLE ||
         engines[i].atr == INVALID_HANDLE)
         return INIT_FAILED;
   }

   Print("DTS v1.10 initialized - execution disabled.");
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

double CalculateStopDistance(int index)
{
   double atr;

   if(!ReadIndicator(engines[index].atr, atr))
      return 0.0;

   return atr * InpStopATRMultiplier;
}

double CalculateRiskMoney()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   return equity * InpRiskPercent / 100.0;
}

double CalculateVolume(string symbol, double stopDistance)
{
   if(stopDistance <= 0.0)
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

   if(tickSize <= 0.0 || tickValue <= 0.0 ||
      volumeStep <= 0.0)
      return 0.0;

   double riskMoney = CalculateRiskMoney();

   double lossPerLot =
      (stopDistance / tickSize) * tickValue;

   if(lossPerLot <= 0.0)
      return 0.0;

   double rawVolume = riskMoney / lossPerLot;

   double volume =
      MathFloor(rawVolume / volumeStep) * volumeStep;

   if(volume < minVolume)
      return 0.0;

   if(volume > maxVolume)
      volume = MathFloor(maxVolume / volumeStep) * volumeStep;

   return NormalizeDouble(volume, 8);
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

   if(atr <= 0.0)
      return "INVALID ATR";

   if(fast > slow && rsi >= InpBullishRSI)
      return "BULLISH";

   if(fast < slow && rsi <= InpBearishRSI)
      return "BEARISH";

   return "NEUTRAL";
}

void OnTick()
{
   string dashboard = "DTS STRATEGIC AI EA v1.10\n";
   dashboard += "QUANT + RISK ENGINE\n";
   dashboard += "AUTOMATIC EXECUTION: OFF\n";
   dashboard += "RISK: 0.5% EQUITY\n\n";

   for(int i = 0; i < ArraySize(engines); i++)
   {
      string symbol = engines[i].symbol;
      string signal = GenerateSignal(i);

      double stopDistance = CalculateStopDistance(i);
      double volume = CalculateVolume(symbol, stopDistance);

      dashboard += symbol + "\n";
      dashboard += "Signal: " + signal + "\n";
      dashboard += "Stop distance: " +
         DoubleToString(stopDistance, 5) + "\n";
      dashboard += "Estimated volume: " +
         DoubleToString(volume, 2) + "\n\n";
   }

   Comment(dashboard);
}
