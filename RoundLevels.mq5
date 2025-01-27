//+------------------------------------------------------------------+
//|                                                  RoundLevels.mq5 |
//|                                  Copyright © 2025, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2025 www.EarnForex.com"
#property link      "https://www.earnforex.com/metatrader-indicators/Round-Levels/"
#property version   "1.03"

#property description "Generates round level zone background shading on chart."

#property indicator_chart_window
#property indicator_plots 0

input int Levels = 5; // Levels - number of level zones in each direction.
input int Interval = 50; // Interval between zones in points.
input int ZoneWidth = 10; // Zone width in points.
input color ColorUp = clrFireBrick;
input color ColorDn = clrDarkGreen;
input bool InvertZones = false; // Invert zones to shade the areas between round numbers.
input bool ZonesAsBackground = true;
input bool DrawLines = false; // Draw lines on levels.
input color LineColor = clrDarkGray;
input int LineWidth = 1;
input ENUM_LINE_STYLE LineStyle = STYLE_DASHDOT;
input bool LinesAsBackground = false;
input bool ShowLineLabels = false;
input color LineLabelColor = clrWhite;
input string ObjectPrefix = "RoundLevels";
input string Comment_1 = "======================="; // Notification Options
input bool EnableNotify = false;                    // Enable Notifications Feature
input bool SendAlert = true;                        // Send Alert Notification
input bool SendApp = false;                         // Send Notification to Mobile
input bool SendEmail = false;                       // Send Notification via Email
input int AlertDelay = 5;                           // Alert Delay, seconds

enum direction
{
    Up,
    Down
};

datetime LastNotificationTime;

void OnInit()
{
    LastNotificationTime = TimeCurrent();
}

void OnDeinit(const int reason)
{
    ObjectsDeleteAll(0, ObjectPrefix);
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime& time[],
                const double& open[],
                const double& high[],
                const double& low[],
                const double& close[],
                const long& tick_volume[],
                const long& volume[],
                const int& spread[])
{
    double starting_price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);

    for (int i = 0; i < Levels; i++)
    {
        // Calculate price levels below and above the current price.
        double lvl_down = FindNextLevel(NormalizeDouble(starting_price - i * Interval * _Point, _Digits), Down);
        double lvl_up = FindNextLevel(NormalizeDouble(starting_price + i * Interval * _Point, _Digits), Up);

        // Calculate and draw rectangle below current price.
        string name = ObjectPrefix + "D" + IntegerToString(i);
        double price1, price2;
        if (InvertZones)
        {
            price1 = lvl_down - (ZoneWidth / 2 * _Point);
            price2 = lvl_down - ((Interval - ZoneWidth / 2) * _Point);
        }
        else
        {
            price1 = lvl_down + (ZoneWidth / 2 * _Point);
            price2 = lvl_down - (ZoneWidth / 2 * _Point);
        }
        DrawRectangle(name, price1, price2, ColorDn);
        name = ObjectPrefix + "LD" + IntegerToString(i);
        if (DrawLines) DrawLine(name, lvl_down);
        Notify(price1, price2);

        // Calculate and draw rectangle above current price.
        name = ObjectPrefix + "U" + IntegerToString(i);
        if (InvertZones)
        {
            price1 = lvl_up + ((Interval - ZoneWidth / 2) * _Point);
            price2 = lvl_up + (ZoneWidth / 2 * _Point);
        }
        else
        {
            price1 = lvl_up + (ZoneWidth / 2 * _Point);
            price2 = lvl_up - (ZoneWidth / 2 * _Point);
        }
        DrawRectangle(name, price1, price2, ColorUp);
        name = ObjectPrefix + "LU" + IntegerToString(i);
        if (DrawLines) DrawLine(name, lvl_up);
        Notify(price1, price2);
    }

    // Center level required for inverted zones.
    if (InvertZones)
    {
        double lvl_down = FindNextLevel(NormalizeDouble(starting_price, _Digits), Down);
        double lvl_up = FindNextLevel(NormalizeDouble(starting_price, _Digits), Up);
        string name = ObjectPrefix + "C";
        double price1 = lvl_up - (ZoneWidth / 2 * _Point);
        double price2 = lvl_down + (ZoneWidth / 2 * _Point);
        DrawRectangle(name, price1, price2, (ColorDn + ColorUp) / 2);
        Notify(price1, price2);
    }

    return 0;
}

double FindNextLevel(const double sp, const direction dir)
{
    // Multiplier for getting number of points in the price.
    double multiplier = MathPow(10, _Digits);
    // Integer price (nubmer of points in the price).
    int integer_price = (int)MathRound(sp * MathPow(10, _Digits));
    // Distance from the next round number down.
    int distance = integer_price % Interval;
    if (dir == Down)
    {
        return NormalizeDouble(MathRound(integer_price - distance) / multiplier, _Digits);
    }
    else if (dir == Up)
    {
        return NormalizeDouble((integer_price + (Interval - distance)) / multiplier, _Digits);
    }
    return EMPTY_VALUE;
}

void DrawRectangle(const string name, const double price1, const double price2, const color colour)
{
    if (ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_RECTANGLE, 0, 0, 0);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price1);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price2);
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, D'1970.01.01');
    ObjectSetInteger(0, name, OBJPROP_TIME, 1, D'3000.12.31');
    ObjectSetInteger(0, name, OBJPROP_COLOR, colour);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, ZonesAsBackground);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    if ((!DrawLines) && (ShowLineLabels))
    {
        DrawLineLabel(name + "_LL", (price1 + price2) / 2);
    }
}

void DrawLine(const string name, const double price)
{
    if (ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, LineColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, LineStyle);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, LinesAsBackground);
    if (ShowLineLabels)
    {
        DrawLineLabel(name + "_LL", price);
    }
}


void DrawLineLabel(const string name, const double price)
{
    if (ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_ARROW_RIGHT_PRICE, 0, 0, 0);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, iTime(Symbol(), Period(), 0));
    ObjectSetInteger(0, name, OBJPROP_COLOR, LineLabelColor);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void Notify(double price1, double price2)
{
    if ((!EnableNotify) || ((!SendAlert) && (!SendApp) && (!SendEmail))) return;
    if (TimeCurrent() - LastNotificationTime < AlertDelay) return;

    if ((SymbolInfoDouble(Symbol(), SYMBOL_BID) > MathMax(price2, price1)) || (SymbolInfoDouble(Symbol(), SYMBOL_BID) < MathMin(price2, price1))) return;
    
    string EmailSubject = "RoundLevels " + Symbol() + " Notification";
    string EmailBody = AccountInfoString(ACCOUNT_COMPANY) + " - " + AccountInfoString(ACCOUNT_NAME) + " - " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\r\nRoundLevels Notification for " + Symbol() + " @ " + EnumToString((ENUM_TIMEFRAMES)Period()) + "\r\n";
    string AlertText = "";
    string AppText = AccountInfoString(ACCOUNT_COMPANY) + " - " + AccountInfoString(ACCOUNT_NAME) + " - " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " - RoundLevels - " + Symbol() + " @ " + EnumToString((ENUM_TIMEFRAMES)Period()) + " - ";
    
    string Text = "Bid Price (" + DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), _Digits) + ") inside a Zone (" + DoubleToString(price2, _Digits) + "-" + DoubleToString(price1, _Digits) + ")";

    EmailBody += Text;
    AlertText += Text;
    AppText += Text;
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
    
    LastNotificationTime = TimeCurrent();
}
//+------------------------------------------------------------------+