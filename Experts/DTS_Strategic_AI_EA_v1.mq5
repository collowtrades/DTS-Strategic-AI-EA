
#property strict
#property version "1.20"
#property description "DTS Strategic AI EA - Quantitative Signal and Risk Engine"

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
};

SymbolEngine engines[];

int OnInit()
{
   if(InpRiskPercent <= 0 ||
      InpRiskPercent > 0.5 ||
      InpMaxSpreadPoints <= 0)
   {
      Print("Invalid risk or spread configuration.");
      return INIT_PARAMETERS_INCORRECT;
   }

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

   Print("DTS Strategic AI EA v1.20 initialized.");
   Print("Signal generation only. Execution disabled.");

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
      (stopDistance / tickSize) * tickValue;

   if(lossPerLot <= 0)
      return 0.0;

   double rawVolume =
      CalculateRiskMoney() / lossPerLot;

   double volume =
      MathFloor(rawVolume / volumeStep) * volumeStep;

   if(volume < minVolume)
      return 0.0;

   if(volume > maxVolume)
      volume = MathFloor(maxVolume / volumeStep)
               * volumeStep;

   return NormalizeDouble(volume, 8);
}

string GenerateSignal(
   int index,
   int &quality,
   string &reason)
{
   double fast, slow, rsi, atr;

   quality = 0;
   reason = "";

   if(!ReadIndicator(engines[index].fastEMA, fast) ||
      !ReadIndicator(engines[index].slowEMA, slow) ||
      !ReadIndicator(engines[index].rsi, rsi) ||
      !ReadIndicator(engines[index].atr, atr))
   {
      reason = "Indicator data unavailable";
      return "WAITING FOR DATA";
   }

   if(atr <= 0)
   {
      reason = "Invalid ATR";
      return "WAITING";
   }

   quality++;

   bool bullishTrend = fast > slow;
   bool bearishTrend = fast < slow;

   if(bullishTrend)
   {
      quality++;

      if(rsi >= InpBullishRSI)
      {
         quality++;
         reason = "Bullish conditions confirmed";
         return "BULLISH";
      }

      reason = "Bullish trend, RSI not confirmed";
      return "NEUTRAL";
   }

   if(bearishTrend)
   {
      quality++;

      if(rsi <= InpBearishRSI)
      {
         quality++;
         reason = "Bearish conditions confirmed";
         return "BEARISH";
      }

      reason = "Bearish trend, RSI not confirmed";
      return "NEUTRAL";
   }

   reason = "EMA trend not established";
   return "NEUTRAL";
}

void OnTick()
{
   string dashboard =
      "DTS STRATEGIC AI EA v1.20\n";

   dashboard += "QUANTITATIVE SIGNAL ENGINE\n";
   dashboard += "AUTOMATIC EXECUTION: OFF\n";
   dashboard += "RISK SETTING: 0.5%\n\n";

   for(int i = 0; i < ArraySize(engines); i++)
   {
      string symbol = engines[i].symbol;

      double spread = GetSpreadPoints(symbol);

      dashboard += symbol + "\n";

      if(spread < 0)
      {
         dashboard += "Spread: UNAVAILABLE\n";
         dashboard += "Status: DATA ERROR\n\n";
         continue;
      }

      dashboard += "Spread: " +
         DoubleToString(spread, 1) + " points\n";

      if(spread > InpMaxSpreadPoints)
      {
         dashboard += "Signal: REJECTED\n";
         dashboard += "Reason: High spread\n\n";
         continue;
      }

      int quality = 0;
      string reason;

      string signal =
         GenerateSignal(i, quality, reason);

      double stopDistance =
         CalculateStopDistance(i);

      double volume =
         CalculateVolume(symbol, stopDistance);

      dashboard += "Signal: " + signal + "\n";

      dashboard += "Quality: " +
         IntegerToString(quality) + "/3\n";

      dashboard += "Reason: " + reason + "\n";

      dashboard += "Stop distance: " +
         DoubleToString(stopDistance, 5) + "\n";

      dashboard += "Estimated volume: " +
         DoubleToString(volume, 2) + "\n\n";
   }

   Comment(dashboard);
}
