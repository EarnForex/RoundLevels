//+------------------------------------------------------------------+
//|                                                  RoundLevels.mq5 |
//|                                  Copyright © 2026, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2026 www.EarnForex.com"
#property link      "https://www.earnforex.com/indicators/Round-Levels/"
#property version   "1.04"

#property description "Generates round level zone background shading on the chart, with optional horizontal lines, labels, alerts, and a hide/show button."

#property indicator_chart_window
#property indicator_plots 0

enum ENUM_BUTTON_CORNER
{
    UpperLeft = CORNER_LEFT_UPPER,   // Upper Left
    LowerLeft = CORNER_LEFT_LOWER,   // Lower Left
    UpperRight = CORNER_RIGHT_UPPER, // Upper Right
    LowerRight = CORNER_RIGHT_LOWER, // Lower Right
    None                             // None (no button)
};

input string Comment_0 = "======================="; // Main
input int Levels = 5; // Levels - number of level zones in each direction.
input int Interval = 0; // Interval between zones in points. 0 = auto (based on visible chart range).
input int ZoneWidth = 0; // Zone width in points. 0 = auto (based on Interval).
input string ObjectPrefix = "RoundLevels";
input string Comment_1 = "======================="; // Visuals
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
input ENUM_BUTTON_CORNER ButtonCorner = None; // Chart corner for the Hide/Show button.
input string Comment_2 = "======================="; // Notifications
input bool EnableNotify = false;                    // Enable Notifications Feature
input bool SendAlert = true;                        // Send Alert Notification
input bool SendApp = false;                         // Send Notification to Mobile
input bool SendEmail = false;                       // Send Notification via Email
input bool SendSound = false;                       // Sound Alert
input string SoundFile = "alert.wav";               // Sound File
input int AlertDelay = 5;                           // Alert Delay, seconds

enum direction
{
    Up,
    Down
};

int EffectiveInterval;  // User-provided Interval, or auto-computed if Interval == 0.
int EffectiveZoneWidth; // User-provided ZoneWidth, or auto-computed if ZoneWidth == 0.
datetime LastNotificationTime;
string ButtonName;
string StateVarName;
bool Hidden = false;
double Multiplier; // Multiplier for getting number of points in the price.
double PrevLevel = 0;
double DPIScale;     // Scaling factor for the Hide/Show button based on the screen DPI (1.0 at the standard 96 DPI).

void OnInit()
{
    if (Interval < 0) Alert("Interval should be non-negative (0 = auto). Interval = ", Interval);
    if (ZoneWidth < 0) Alert("ZoneWidth should be non-negative (0 = auto). ZoneWidth = ", ZoneWidth);
    if (Levels <= 0) Alert("Levels should be a positive number. Levels = ", Levels);
    Multiplier = MathPow(10, _Digits);
    // Compute the effective Interval (auto when the input is 0).
    if (Interval > 0)
    {
        EffectiveInterval = Interval;
    }
    else
    {
        double price_max = ChartGetDouble(0, CHART_PRICE_MAX);
        double price_min = ChartGetDouble(0, CHART_PRICE_MIN);
        double range_points = (price_max - price_min) / _Point;
        // Target one interval per ~2*Levels zones, so the visible range roughly accommodates the requested number of levels above and below.
        double target = range_points / (2.0 * MathMax(Levels, 1));
        EffectiveInterval = SnapToNice(target);
        if (EffectiveInterval < 1) EffectiveInterval = 1;
        Print("RoundLevels: auto Interval = ", EffectiveInterval, " points (visible range = ", DoubleToString(range_points, 0), " points).");
    }
    // Compute the effective ZoneWidth (auto when the input is 0).
    if (ZoneWidth > 0)
    {
        EffectiveZoneWidth = ZoneWidth;
    }
    else
    {
        EffectiveZoneWidth = EffectiveInterval / 5;
        if (EffectiveZoneWidth < 1) EffectiveZoneWidth = 1;
        Print("RoundLevels: auto ZoneWidth = ", EffectiveZoneWidth, " points.");
    }
    LastNotificationTime = TimeCurrent();
    if (ButtonCorner != None)
    {
        ButtonName = ObjectPrefix + "_Button";
        StateVarName = ObjectPrefix + "_Hidden_" + IntegerToString(ChartID());
        DPIScale = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0;
        // Restore hidden/shown state saved by a previous deinit (timeframe change, recompile, etc.), then delete the variable.
        if (GlobalVariableCheck(StateVarName))
        {
            Hidden = (GlobalVariableGet(StateVarName) != 0);
            GlobalVariableDel(StateVarName);
        }
        CreateButton();
    }
}

void OnDeinit(const int reason)
{
    if (ButtonCorner != None)
    {
        // Preserve hidden/shown state across reinitializations (timeframe change, recompile, parameter change, etc.).
        // Do NOT save it when the user removes the indicator or closes the chart, so a fresh load starts from the default.
        if (reason != REASON_REMOVE && reason != REASON_CHARTCLOSE)
        {
            GlobalVariableSet(StateVarName, Hidden ? 1 : 0);
        }
    }
    ObjectsDeleteAll(0, ObjectPrefix + "_");
}

void OnChartEvent(const int id,
                  const long& lparam,
                  const double& dparam,
                  const string& sparam)
{
    if (id != CHARTEVENT_OBJECT_CLICK) return;
    if (sparam != ButtonName) return;
    Hidden = !Hidden;
    ObjectSetInteger(0, ButtonName, OBJPROP_STATE, false);
    ObjectSetString(0, ButtonName, OBJPROP_TEXT, Hidden ? "Show Lines" : "Hide Lines");
    ObjectSetString(0, ButtonName, OBJPROP_TOOLTIP, Hidden ? "Show Round Levels indicator lines/zones" : "Hide Round Levels indicator lines/zones");
    SetLevelsVisibility(!Hidden);
    ChartRedraw();
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
    if (EffectiveInterval <= 0) return 0;
    
    double starting_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double check_level = FindNextLevel(starting_price, Down); // To verify that levels haven't changed.
    if (MathAbs(check_level - PrevLevel) < _Point / 2 && (!EnableNotify || (!SendAlert && !SendApp && !SendEmail && !SendSound))) return rates_total; // Prevent recalculation on the same price.
    PrevLevel = check_level;

    for (int i = 0; i < Levels; i++)
    {
        // Calculate price levels below and above the current price.
        double lvl_down = FindNextLevel(starting_price - i * EffectiveInterval * _Point, Down);
        double lvl_up = FindNextLevel(starting_price + i * EffectiveInterval * _Point, Up);
        // Calculate and draw rectangle below current price.
        string name = ObjectPrefix + "_D" + IntegerToString(i);
        double price1, price2;
        if (InvertZones)
        {
            price1 = lvl_down - (EffectiveZoneWidth / 2 * _Point);
            price2 = lvl_down - ((EffectiveInterval - EffectiveZoneWidth / 2) * _Point);
        }
        else
        {
            price1 = lvl_down + (EffectiveZoneWidth / 2 * _Point);
            price2 = lvl_down - (EffectiveZoneWidth / 2 * _Point);
        }
        DrawRectangle(name, price1, price2, ColorDn);
        name = ObjectPrefix + "_LD" + IntegerToString(i);
        if (DrawLines) DrawLine(name, lvl_down);
        Notify(price1, price2);

        // Calculate and draw rectangle above current price.
        name = ObjectPrefix + "_U" + IntegerToString(i);
        if (InvertZones)
        {
            price1 = lvl_up + ((EffectiveInterval - EffectiveZoneWidth / 2) * _Point);
            price2 = lvl_up + (EffectiveZoneWidth / 2 * _Point);
        }
        else
        {
            price1 = lvl_up + (EffectiveZoneWidth / 2 * _Point);
            price2 = lvl_up - (EffectiveZoneWidth / 2 * _Point);
        }
        DrawRectangle(name, price1, price2, ColorUp);
        name = ObjectPrefix + "_LU" + IntegerToString(i);
        if (DrawLines) DrawLine(name, lvl_up);
        Notify(price1, price2);
    }

    // Center level required for inverted zones.
    if (InvertZones)
    {
        double lvl_down = FindNextLevel(starting_price, Down);
        double lvl_up = FindNextLevel(starting_price, Up);
        string name = ObjectPrefix + "_C";
        double price1 = lvl_up - (EffectiveZoneWidth / 2 * _Point);
        double price2 = lvl_down + (EffectiveZoneWidth / 2 * _Point);
        DrawRectangle(name, price1, price2, (ColorDn + ColorUp) / 2);
        Notify(price1, price2);
    }

    return rates_total;
}

double FindNextLevel(const double sp, const direction dir)
{
    // Integer price (nubmer of points in the price).
    int integer_price = (int)MathRound(sp * Multiplier);
    // Distance from the next round number down.
    int distance = integer_price % EffectiveInterval;
    if (dir == Down)
    {
        return NormalizeDouble((integer_price - distance) / Multiplier, _Digits);
    }
    else if (dir == Up)
    {
        return NormalizeDouble((integer_price + (EffectiveInterval - distance)) / Multiplier, _Digits);
    }
    return EMPTY_VALUE;
}

void DrawRectangle(const string name, const double price1, const double price2, const color colour)
{
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, 0, 0);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price1);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 1, price2);
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, D'1970.01.01');
    ObjectSetInteger(0, name, OBJPROP_TIME, 1, D'3000.12.31');
    ObjectSetInteger(0, name, OBJPROP_COLOR, colour);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, ZonesAsBackground);
    ObjectSetInteger(0, name, OBJPROP_FILL, true);
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, Hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    if (!DrawLines && ShowLineLabels)
    {
        DrawLineLabel(name + "_LL", (price1 + price2) / 2);
    }
}

void DrawLine(const string name, const double price)
{
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, 0);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
    ObjectSetInteger(0, name, OBJPROP_COLOR, LineColor);
    ObjectSetInteger(0, name, OBJPROP_STYLE, LineStyle);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, LinesAsBackground);
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, Hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
    if (ShowLineLabels)
    {
        DrawLineLabel(name + "_LL", price);
    }
}

void DrawLineLabel(const string name, const double price)
{
    ObjectCreate(0, name, OBJ_ARROW_RIGHT_PRICE, 0, 0, 0);
    ObjectSetDouble(0, name, OBJPROP_PRICE, 0, price);
    ObjectSetInteger(0, name, OBJPROP_TIME, 0, iTime(Symbol(), Period(), 0));
    ObjectSetInteger(0, name, OBJPROP_COLOR, LineLabelColor);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, LineWidth);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, name, OBJPROP_BACK, false);
    ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, Hidden ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS);
}

void Notify(double price1, double price2)
{
    if (!EnableNotify || (!SendAlert && !SendApp && !SendEmail && !SendSound)) return;
    if (TimeCurrent() - LastNotificationTime < AlertDelay) return;

    if (SymbolInfoDouble(Symbol(), SYMBOL_BID) > MathMax(price2, price1) || SymbolInfoDouble(Symbol(), SYMBOL_BID) < MathMin(price2, price1)) return;
    
    string EmailSubject = "RoundLevels " + Symbol() + " Notification";
    string EmailBody = AccountInfoString(ACCOUNT_COMPANY) + " - " + AccountInfoString(ACCOUNT_NAME) + " - " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "\r\nRoundLevels Notification for " + Symbol() + " @ " + EnumToString(Period()) + "\r\n";
    string AlertText = "";
    string AppText = AccountInfoString(ACCOUNT_COMPANY) + " - " + AccountInfoString(ACCOUNT_NAME) + " - " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + " - RoundLevels - " + Symbol() + " @ " + EnumToString(Period()) + " - ";
    
    string Text = "Bid Price (" + DoubleToString(SymbolInfoDouble(Symbol(), SYMBOL_BID), _Digits) + ") inside a Zone (" + DoubleToString(price2, _Digits) + "-" + DoubleToString(price1, _Digits) + ")";

    EmailBody += Text;
    AlertText += Text;
    AppText += Text;
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending an email: " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending a push notification: " + IntegerToString(GetLastError()));
    }
    if (SendSound)
    {
        if (!PlaySound(SoundFile)) Print("Error playing a sound: " + IntegerToString(GetLastError()));
    }

    LastNotificationTime = TimeCurrent();
}

void CreateButton()
{
    ObjectCreate(0, ButtonName, OBJ_BUTTON, 0, 0, 0);
    int button_width = (int)MathRound(75 * DPIScale);
    int button_height = (int)MathRound(20 * DPIScale);
    int margin = (int)MathRound(10 * DPIScale);
    int font_size = (int)MathRound(10 * DPIScale);
    int xdist = margin;
    int ydist = margin;
    // Compensate for the anchor point (top-left of the button) so the button stays fully on-chart for right/bottom corners.
    if (ButtonCorner == UpperRight || ButtonCorner == LowerRight) xdist = button_width + margin;
    if (ButtonCorner == LowerLeft || ButtonCorner == LowerRight) ydist = button_height + margin;
    ObjectSetInteger(0, ButtonName, OBJPROP_CORNER, ButtonCorner);
    ObjectSetInteger(0, ButtonName, OBJPROP_XDISTANCE, xdist);
    ObjectSetInteger(0, ButtonName, OBJPROP_YDISTANCE, ydist);
    ObjectSetInteger(0, ButtonName, OBJPROP_XSIZE, button_width);
    ObjectSetInteger(0, ButtonName, OBJPROP_YSIZE, button_height);
    ObjectSetInteger(0, ButtonName, OBJPROP_FONTSIZE, font_size);
    ObjectSetInteger(0, ButtonName, OBJPROP_BGCOLOR, clrDarkGray);
    ObjectSetInteger(0, ButtonName, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, ButtonName, OBJPROP_BORDER_COLOR, clrBlack);
    ObjectSetInteger(0, ButtonName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, ButtonName, OBJPROP_STATE, false);
    ObjectSetString(0, ButtonName, OBJPROP_TEXT, Hidden ? "Show Lines" : "Hide Lines");
    ObjectSetString(0, ButtonName, OBJPROP_TOOLTIP, Hidden ? "Show Round Levels indicator lines/zones" : "Hide Round Levels indicator lines/zones");
}

void SetLevelsVisibility(const bool visible)
{
    // OBJ_ALL_PERIODS shows the object on every timeframe; a value with none of the period bits set (0) hides it on all of them.
    long tf = visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS;
    int total = ObjectsTotal(0, -1, -1);
    for (int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, -1, -1);
        // Toggle visibility of every object created by this indicator except the button itself.
        if (StringFind(name, ObjectPrefix + "_") == 0 && name != ButtonName)
        {
            ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tf);
        }
    }
}

// Snap a positive number to the nearest value in the 1-2-5 sequence at the appropriate power of 10 (e.g. 33 -> 20, 70 -> 50, 150 -> 100).
// Uses geometric midpoints so each bucket covers an equal log-distance.
int SnapToNice(const double value)
{
    if (value < 1) return 1;
    double magnitude = MathPow(10, MathFloor(MathLog(value) / MathLog(10.0)));
    double normalized = value / magnitude;
    int nice;
    if (normalized < 1.414) nice = 1;       // sqrt(2)
    else if (normalized < 3.162) nice = 2;  // sqrt(10)
    else if (normalized < 7.071) nice = 5;  // sqrt(50)
    else nice = 10;
    return (int)(nice * magnitude);
}
//+------------------------------------------------------------------+