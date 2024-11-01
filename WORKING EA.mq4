//+------------------------------------------------------------------+
//|                 AMATERASU BTC EA.mq4                             |
//| Copyright © 2024 AMATERASU. All Rights Reserved.                 |
//| For questions, sets, or inquiries, visit: https://discord.gg/PEcBTAZR9n |
//| If you identify as a shark, send me a DM!                        |
//+------------------------------------------------------------------+
#property strict

//--- Input parameters
input double InitialLotSize = 0.01;
input double MaxLoss = -300.0;
input double ProfitTarget = 50.0;   // TP in pips
input double LossTarget = 30.0;     // SL in pips
input double MoveStopLossProfit = 50.0;
input double MoveStopLoss = 5.0;
input bool UseMartingale = true;
input double MartingaleMultiplier = 1.5;
input double AntiMartingaleMultiplier = 0.5;
input double FixedLotSize = 0.01;
input bool UseFixedLotSize = false;
input ENUM_TIMEFRAMES TradingTimeframe = PERIOD_M1;
input int StartHour = 0;
input int EndHour = 24;
input bool TradeMonday = true;
input bool TradeTuesday = true;
input bool TradeWednesday = true;
input bool TradeThursday = true;
input bool TradeFriday = true;
input bool TradeSaturday = true;
input bool TradeSunday = true;
input double Slippage = 3.0;
input double MaxSpread = 20.0;
input bool EnableLogging = true;
input bool EnableAlerts = true;
input string BotName = "AMATERASU BTC EA";
input bool EnableTradingInput = true;
input int NumOfTradesToTrack = 5;  // Number of trades to track for win percentage

//--- Global variables
int MagicNumber = 123456;
double CurrentLotSize = 0.0;
bool EnableTrading;
datetime lastTradeTime = 0;
double spread, volatility;
double lastTrades[]; // Array to store win/loss of recent trades

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Initialize lastTrades array with size NumOfTradesToTrack
    ArrayResize(lastTrades, NumOfTradesToTrack);
    for (int i = 0; i < NumOfTradesToTrack; i++) {
        lastTrades[i] = 0.0;
    }

    // Perform initial checks before confirming initialization
    if (!CanPlaceTrades())
    {
        Print("Error: Cannot place trades due to one or more conditions not met.");
        return (INIT_FAILED);
    }

    EventSetTimer(1);
    CurrentLotSize = InitialLotSize;
    EnableTrading = EnableTradingInput;
    lastTradeTime = 0;
    UpdateIndicators();
    Comment(BotName, "\nStatus: Initialized\nSpread: ", spread, "\nVolatility: ", volatility, 
            "\nWin Rate (last ", NumOfTradesToTrack, "): ", CalculateWinPercentage(), "%\nCopyright © 2024 AMATERASU. All Rights Reserved.\nFor questions, sets, or inquiries, visit: https://discord.gg/PEcBTAZR9n\nIf you identify as a shark, send me a DM!");
    return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    Comment("");
}

//+------------------------------------------------------------------+
//| Expert timer function                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
    if (Period() != TradingTimeframe)
        return;

    int currentHour = TimeHour(TimeCurrent());
    int currentDay = TimeDayOfWeek(TimeCurrent());

    if ((currentHour < StartHour || currentHour >= EndHour) || !IsTradingDay(currentDay))
        return;

    CheckSafetyConditions();

    if (EnableTrading)
        ManageTrades();
}

//+------------------------------------------------------------------+
//| IsTradingDay function                                            |
//+------------------------------------------------------------------+
bool IsTradingDay(int day)
{
    switch (day)
    {
        case 1: return TradeMonday;
        case 2: return TradeTuesday;
        case 3: return TradeWednesday;
        case 4: return TradeThursday;
        case 5: return TradeFriday;
        case 6: return TradeSaturday;
        case 0: return TradeSunday;
        default: return false;
    }
}

//+------------------------------------------------------------------+
//| ManageTrades function                                            |
//+------------------------------------------------------------------+
void ManageTrades()
{
    UpdateIndicators();

    datetime lastCandleTime = iTime(NULL, TradingTimeframe, 0);

    if (lastCandleTime <= lastTradeTime || IsTradeOpen())
        return; // Ensure trade is placed only once per candle and no open trade exists

    lastTradeTime = lastCandleTime;

    int ticket;
    double lotSize = UseFixedLotSize ? FixedLotSize : CurrentLotSize;

    double tpPrice, slPrice;
    double price = 0;

    if (IsBullish())
    {
        price = Ask;
        tpPrice = price + ProfitTarget * Point;  // TP is ProfitTarget pips above entry price
        slPrice = price - LossTarget * Point;   // SL is LossTarget pips below entry price

        ticket = OrderSend(Symbol(), OP_BUY, lotSize, NormalizeDouble(price, Digits), (int)Slippage, 
                           NormalizeDouble(slPrice, Digits), NormalizeDouble(tpPrice, Digits), "Buy Order", MagicNumber, 0, Blue);
        if (ticket < 0)
        {
            Print("Error: Buy order failed. Error code: ", GetLastError());
        }
        else
        {
            LogTradeAction("Buy Entry", lotSize, price);
            UpdateWinRecord(true);
        }
    }
    else
    {
        price = Bid;
        tpPrice = price - ProfitTarget * Point;  // TP is ProfitTarget pips below entry price
        slPrice = price + LossTarget * Point;   // SL is LossTarget pips above entry price

        ticket = OrderSend(Symbol(), OP_SELL, lotSize, NormalizeDouble(price, Digits), (int)Slippage, 
                           NormalizeDouble(slPrice, Digits), NormalizeDouble(tpPrice, Digits), "Sell Order", MagicNumber, 0, Red);
        if (ticket < 0)
        {
            Print("Error: Sell order failed. Error code: ", GetLastError());
        }
        else
        {
            LogTradeAction("Sell Entry", lotSize, price);
            UpdateWinRecord(true);
        }
    }
    Comment(BotName, "\nSpread: ", spread, "\nVolatility: ", volatility, 
            "\nWin Rate (last ", NumOfTradesToTrack, "): ", CalculateWinPercentage(), "%\nCopyright © 2024 AMATERASU. All Rights Reserved.\nFor questions, sets, or inquiries, visit: https://discord.gg/PEcBTAZR9n\nIf you identify as a shark, send me a DM!");
}

//+------------------------------------------------------------------+
//| UpdateIndicators function                                        |
//+------------------------------------------------------------------+
void UpdateIndicators()
{
    spread = MarketInfo(Symbol(), MODE_SPREAD);
    volatility = iHigh(NULL, TradingTimeframe, 1) - iLow(NULL, TradingTimeframe, 1);
}

//+------------------------------------------------------------------+
//| IsBullish function                                               |
//+------------------------------------------------------------------+
bool IsBullish()
{
    return (iClose(NULL, TradingTimeframe, 1) > iOpen(NULL, TradingTimeframe, 1));
}

//+------------------------------------------------------------------+
//| UpdateWinRecord function                                         |
//+------------------------------------------------------------------+
void UpdateWinRecord(bool isWin)
{
    // Shift the last trades
    for (int i = NumOfTradesToTrack - 1; i > 0; i--)
    {
        lastTrades[i] = lastTrades[i - 1];
    }
    lastTrades[0] = isWin ? 1.0 : 0.0;
}

//+------------------------------------------------------------------+
//| CalculateWinPercentage function                                  |
//+------------------------------------------------------------------+
double CalculateWinPercentage()
{
    double sum = 0.0;
    for (int i = 0; i < NumOfTradesToTrack; i++)
    {
        sum += lastTrades[i];
    }
    return (sum / NumOfTradesToTrack) * 100.0;
}

//+------------------------------------------------------------------+
//| CheckSafetyConditions function                                   |
//+------------------------------------------------------------------+
void CheckSafetyConditions()
{
    if (AccountEquity() < (AccountBalance() + MaxLoss))
    {
        for (int i = OrdersTotal() - 1; i >= 0; i--)
        {
            if (OrderSelect(i, SELECT_BY_POS))
            {
                if (OrderClose(OrderTicket(), OrderLots(), OrderClosePrice(), (int)Slippage, Yellow))
                {
                    LogTradeAction("Max Drawdown Exceeded - Closing All Trades", OrderLots(), OrderClosePrice());
                }
                else
                {
                    Print("Error: Failed to close order during max drawdown. Error code: ", GetLastError());
                }
            }
        }
        EnableTrading = false;
        Comment("Trading Disabled due to Max Drawdown Exceeded");
    }
}

//+------------------------------------------------------------------+
//| LogTradeAction function                                          |
//+------------------------------------------------------------------+
void LogTradeAction(string action, double lots, double price)
{
    if (EnableLogging)
    {
        Print(action, " | Lots: ", lots, " | Price: ", price, " | Time: ", TimeToStr(TimeCurrent()));
    }
}

//+------------------------------------------------------------------+
//| CanPlaceTrades function                                          |
//+------------------------------------------------------------------+
bool CanPlaceTrades()
{
    if (AccountBalance() < (InitialLotSize * MarketInfo(Symbol(), MODE_TICKVALUE)))
    {
        Print("Error: Insufficient balance to place trades.");
        return false;
    }

    spread = MarketInfo(Symbol(), MODE_SPREAD);
    if (spread > MaxSpread)
    {
        Print("Error: Spread too high. Current spread: ", spread);
        return false;
    }

    if (MarketInfo(Symbol(), MODE_TRADEALLOWED) == 0)
    {
        Print("Error: Trading not allowed on this market.");
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| IsTradeOpen function                                            |
//+------------------------------------------------------------------+
bool IsTradeOpen()
{
    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (OrderSelect(i, SELECT_BY_POS) && OrderType() <= OP_SELL)
        {
            if (OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
            {
                return true;
            }
        }
    }
    return false;
}
