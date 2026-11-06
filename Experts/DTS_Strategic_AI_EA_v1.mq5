
#property strict
#property version "1.40"
#property description "DTS Strategic AI EA - Dashboard and Signal Logger"

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
input int InpScanIntervalSeconds = 1;

input bool InpEnableExecution = false;

input string InpLogFile = "DTS\\DTS_Signal_Log.csv";

struct SymbolEngine
{
   string symbol;

   int fastEMA;
   int slowEMA;
   int rsi;
   int atr;

   datetime lastBar;
   datetime signalBarTime;

   string baseSignal;
   string baseReason;

   string signal;
   string reason;

   string lastLoggedSignal;
   string lastLoggedReason;

   int quality;

   double spread;
   double stopDistance;
   double volume;
};

SymbolEngine engines[];

int logHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Release indicator handles                                        |
//+------------------------------------------------------------------+
void ReleaseIndicators()
{
   for(int i = 0; i < ArraySize(engines); i++)
   {
      if(engines[i].fastEMA != INVALID_HANDLE)
         IndicatorRelease(engines[i].fastEMA);

      if(engines[i].slowEMA != INVALID_HANDLE)
         IndicatorRelease(engines[i].slowEMA);

      if(engines[i].rsi != INVALID_HANDLE)
         IndicatorRelease(engines[i].rsi);

      if(engines[i].atr != INVALID_HANDLE)
         IndicatorRelease(engines[i].atr);
   }
}

//+------------------------------------------------------------------+
//| Initialize CSV logging                                           |
//+------------------------------------------------------------------+
bool InitializeLogger()
{
   ResetLastError();

   logHandle = FileOpen(
      InpLogFile,
      FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ,
      ',');

   if(logHandle == INVALID_HANDLE)
   {
      Print("DTS logger initialization failed. Error: ",
            GetLastError());
      return false;
   }

   if(FileSize(logHandle) == 0)
   {
      FileWrite(
         logHandle,
         "EventTime",
         "SignalBarTime",
         "Symbol",
         "Timeframe",
         "Signal",
         "Reason",
         "Quality",
         "SpreadPoints",
         "StopDistance",
         "EstimatedVolume");
   }

   FileSeek(logHandle, 0, SEEK_END);
   FileFlush(logHandle);

   Print("DTS CSV signal logger initialized.");

   return true;
}

//+------------------------------------------------------------------+
//| Write signal event                                               |
//+------------------------------------------------------------------+
void WriteSignalLog(int index)
{
   if(logHandle == INVALID_HANDLE)
      return;

   if(engines[index].signal ==
      engines[index].lastLoggedSignal &&
      engines[index].reason ==
      engines[index].lastLoggedReason)
      return;

   FileWrite(
      logHandle,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      TimeToString(engines[index].signalBarTime,
                   TIME_DATE | TIME_MINUTES),
      engines[index].symbol,
      EnumToString(InpTimeframe),
      engines[index].signal,
      engines[index].reason,
      engines[index].quality,
      DoubleToString(engines[index].spread, 1),
      DoubleToString(engines[index].stopDistance, 5),
      DoubleToString(engines[index].volume, 8));

   FileFlush(logHandle);

   Print(
      "DTS SIGNAL EVENT | ",
      engines[index].symbol,
      " | ",
      engines[index].signal,
      " | ",
      engines[index].reason);

   engines[index].lastLoggedSignal =
      engines[index].signal;

   engines[index].lastLoggedReason =
      engines[index].reason;
}

//+------------------------------------------------------------------+
//| Read indicator value from last closed candle                     |
//+------------------------------------------------------------------+
bool ReadIndicator(int handle, double &value)
{
   double buffer[];

   ArraySetAsSeries(buffer, true);

   if(CopyBuffer(handle, 0, 1, 1, buffer) != 1)
      return false;

   value = buffer[0];

   return true;
}

//+------------------------------------------------------------------+
//| Calculate current spread                                         |
//+------------------------------------------------------------------+
double GetSpreadPoints(string symbol)
{
   MqlTick tick;

   if(!SymbolInfoTick(symbol, tick))
      return -1.0;

   double point =
      SymbolInfoDouble(symbol, SYMBOL_POINT);

   if(point <= 0 || tick.ask <= 0 || tick.bid <= 0)
      return -1.0;

   return (tick.ask - tick.bid) / point;
}

//+------------------------------------------------------------------+
//| Calculate risk budget                                            |
//+------------------------------------------------------------------+
double CalculateRiskMoney()
{
   double equity =
      AccountInfoDouble(ACCOUNT_EQUITY);

   return equity * InpRiskPercent / 100.0;
}

//+------------------------------------------------------------------+
//| Calculate estimated volume                                       |
//+------------------------------------------------------------------+
double CalculateVolume(
   string symbol,
   double stopDistance)
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

   if(tickSize <= 0 ||
      tickValue <= 0 ||
      minVolume <= 0 ||
      maxVolume < minVolume ||
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
      volume =
         MathFloor(maxVolume / volumeStep) * volumeStep;

   return NormalizeDouble(volume, 8);
}

//+------------------------------------------------------------------+
//| Update analysis only when a new candle appears                    |
//+------------------------------------------------------------------+
void UpdateOnNewBar(int index)
{
   string symbol = engines[index].symbol;

   datetime currentBar =
      iTime(symbol, InpTimeframe, 0);

   if(currentBar <= 0)
   {
      engines[index].baseSignal = "WAITING";
      engines[index].baseReason = "Price history unavailable";
      return;
   }

   if(currentBar == engines[index].lastBar)
      return;

   double fast, slow, rsi, atr;

   if(!ReadIndicator(engines[index].fastEMA, fast) ||
      !ReadIndicator(engines[index].slowEMA, slow) ||
      !ReadIndicator(engines[index].rsi, rsi) ||
      !ReadIndicator(engines[index].atr, atr))
   {
      engines[index].baseSignal = "WAITING";
      engines[index].baseReason = "Indicator data unavailable";
      engines[index].quality = 0;
      return;
   }

   if(atr <= 0)
   {
      engines[index].baseSignal = "WAITING";
      engines[index].baseReason = "Invalid ATR";
      engines[index].quality = 0;
      return;
   }

   engines[index].lastBar = currentBar;
   engines[index].signalBarTime =
      iTime(symbol, InpTimeframe, 1);

   engines[index].quality = 1;

   if(fast > slow)
   {
      engines[index].quality = 2;

      if(rsi >= InpBullishRSI)
      {
         engines[index].baseSignal = "BULLISH";
         engines[index].baseReason =
            "Bullish EMA and RSI confirmed";
         engines[index].quality = 3;
      }
      else
      {
         engines[index].baseSignal = "NEUTRAL";
         engines[index].baseReason =
            "Bullish trend without RSI confirmation";
      }
   }
   else if(fast < slow)
   {
      engines[index].quality = 2;

      if(rsi <= InpBearishRSI)
      {
         engines[index].baseSignal = "BEARISH";
         engines[index].baseReason =
            "Bearish EMA and RSI confirmed";
         engines[index].quality = 3;
      }
      else
      {
         engines[index].baseSignal = "NEUTRAL";
         engines[index].baseReason =
            "Bearish trend without RSI confirmation";
      }
   }
   else
   {
      engines[index].baseSignal = "NEUTRAL";
      engines[index].baseReason =
         "EMA trend not established";
   }

   engines[index].stopDistance =
      atr * InpStopATRMultiplier;

   engines[index].volume =
      CalculateVolume(
         symbol,
         engines[index].stopDistance);
}

//+------------------------------------------------------------------+
//| Apply live spread filter                                          |
//+------------------------------------------------------------------+
void ApplySpreadFilter(int index)
{
   double spread =
      GetSpreadPoints(engines[index].symbol);

   engines[index].spread = spread;

   if(spread < 0)
   {
      engines[index].signal = "DATA ERROR";
      engines[index].reason = "Market quote unavailable";
      return;
   }

   if(spread > InpMaxSpreadPoints)
   {
      engines[index].signal = "REJECTED";
      engines[index].reason = "Spread exceeds limit";
      return;
   }

   engines[index].signal =
      engines[index].baseSignal;

   engines[index].reason =
      engines[index].baseReason;
}

//+------------------------------------------------------------------+
//| Build dashboard                                                   |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   string dashboard =
      "================================\n";

   dashboard += " DTS STRATEGIC AI EA v1.40\n";
   dashboard += " INSTITUTIONAL MONITOR\n";
   dashboard += "================================\n";

   dashboard += "Execution: DISABLED\n";
   dashboard += "Risk setting: 0.5%\n";
   dashboard += "Timeframe: " +
      EnumToString(InpTimeframe) + "\n";

   dashboard += "Scan interval: " +
      IntegerToString(InpScanIntervalSeconds) +
      " seconds\n\n";

   for(int i = 0; i < ArraySize(engines); i++)
   {
      dashboard += "-------------------------------\n";

      dashboard += engines[i].symbol + "\n";

      dashboard += "Signal: " +
         engines[i].signal + "\n";

      dashboard += "Reason: " +
         engines[i].reason + "\n";

      dashboard += "Quality: " +
         IntegerToString(engines[i].quality) +
         "/3\n";

      dashboard += "Spread: " +
         DoubleToString(engines[i].spread, 1) +
         " points\n";

      dashboard += "Signal candle: " +
         TimeToString(
            engines[i].signalBarTime,
            TIME_DATE | TIME_MINUTES) + "\n";

      dashboard += "ATR stop distance: " +
         DoubleToString(
            engines[i].stopDistance, 5) + "\n";

      dashboard += "Estimated volume: " +
         DoubleToString(
            engines[i].volume, 8) + "\n\n";
   }

   dashboard += "CSV: DTS/DTS_Signal_Log.csv\n";
   dashboard += "No orders are sent.";

   Comment(dashboard);
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpRiskPercent <= 0 ||
      InpRiskPercent > 0.5 ||
      InpFastEMA <= 0 ||
      InpSlowEMA <= InpFastEMA ||
      InpRSIPeriod <= 0 ||
      InpATRPeriod <= 0 ||
      InpMaxSpreadPoints <= 0 ||
      InpScanIntervalSeconds < 1 ||
      InpStopATRMultiplier <= 0 ||
      InpBullishRSI <= InpBearishRSI)
      return INIT_PARAMETERS_INCORRECT;

   string symbols[];

   int count =
      StringSplit(InpSymbols, ',', symbols);

   if(count <= 0)
      return INIT_FAILED;

   ArrayResize(engines, count);

   for(int i = 0; i < count; i++)
   {
      engines[i].fastEMA = INVALID_HANDLE;
      engines[i].slowEMA = INVALID_HANDLE;
      engines[i].rsi = INVALID_HANDLE;
      engines[i].atr = INVALID_HANDLE;

      StringTrimLeft(symbols[i]);
      StringTrimRight(symbols[i]);

      engines[i].symbol = symbols[i];

      engines[i].lastBar = 0;
      engines[i].signalBarTime = 0;

      engines[i].baseSignal = "WAITING";
      engines[i].baseReason = "Initializing";

      engines[i].signal = "INITIALIZING";
      engines[i].reason = "Waiting for market data";

      engines[i].lastLoggedSignal = "";
      engines[i].lastLoggedReason = "";

      engines[i].quality = 0;
      engines[i].spread = -1;
      engines[i].stopDistance = 0;
      engines[i].volume = 0;

      if(!SymbolSelect(symbols[i], true))
      {
         Print("Symbol selection failed: ", symbols[i]);
         ReleaseIndicators();
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
         Print("Indicator creation failed: ", symbols[i]);
         ReleaseIndicators();
         return INIT_FAILED;
      }
   }

   if(!InitializeLogger())
      Print("Warning: CSV logging unavailable.");

   if(InpEnableExecution)
      Print("Execution setting ignored: order execution is not implemented.");

   if(!EventSetTimer(InpScanIntervalSeconds))
   {
      Print("Timer initialization failed: ", GetLastError());

      ReleaseIndicators();

      if(logHandle != INVALID_HANDLE)
         FileClose(logHandle);

      return INIT_FAILED;
   }

   Print("DTS Strategic AI EA v1.40 initialized.");
   Print("Multi-symbol timer monitoring active.");
   Print("Automatic execution disabled.");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Timer event: independent symbol scanning                         |
//+------------------------------------------------------------------+
void OnTimer()
{
   for(int i = 0; i < ArraySize(engines); i++)
   {
      UpdateOnNewBar(i);
      ApplySpreadFilter(i);
      WriteSignalLog(i);
   }

   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   ReleaseIndicators();

   if(logHandle != INVALID_HANDLE)
   {
      FileFlush(logHandle);
      FileClose(logHandle);
      logHandle = INVALID_HANDLE;
   }

   Comment("");

   Print("DTS Strategic AI EA v1.40 stopped.");
}
