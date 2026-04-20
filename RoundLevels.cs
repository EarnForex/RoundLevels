// -------------------------------------------------------------------------------
//   Generates round level zone background shading on the chart, with optional 
//   horizontal lines, labels, and alerts.
//
//   Version 1.04
//   Copyright 2026, EarnForex.com
//   https://www.earnforex.com/indicators/Round-Levels/
// -------------------------------------------------------------------------------

using System;
using cAlgo.API;

namespace cAlgo
{
    [Indicator(IsOverlay = true, AccessRights = AccessRights.None)]
    public class RoundLevels : Indicator
    {
        // === Main ==================================================================
        [Parameter("Levels (each direction)", DefaultValue = 5, MinValue = 1, Group = "Main")]
        public int Levels { get; set; }

        [Parameter("Interval (points, 0 = auto)", DefaultValue = 0, MinValue = 0, Group = "Main")]
        public int Interval { get; set; }

        [Parameter("Zone Width (points, 0 = auto)", DefaultValue = 0, MinValue = 0, Group = "Main")]
        public int ZoneWidth { get; set; }

        [Parameter("Object Prefix", DefaultValue = "RoundLevels", Group = "Main")]
        public string ObjectPrefix { get; set; }

        // === Visuals ===============================================================
        [Parameter("Color (Above)", DefaultValue = "FireBrick", Group = "Visuals")]
        public Color ColorUp { get; set; }

        [Parameter("Color (Below)", DefaultValue = "DarkGreen", Group = "Visuals")]
        public Color ColorDn { get; set; }

        [Parameter("Zone Opacity (0-255)", DefaultValue = 64, MinValue = 0, MaxValue = 255, Group = "Visuals")]
        public int ZoneOpacity { get; set; }

        [Parameter("Invert Zones", DefaultValue = false, Group = "Visuals")]
        public bool InvertZones { get; set; }

        [Parameter("Draw Lines on Levels", DefaultValue = false, Group = "Visuals")]
        public bool DrawLines { get; set; }

        [Parameter("Line Color", DefaultValue = "DarkGray", Group = "Visuals")]
        public Color LineColor { get; set; }

        [Parameter("Line Thickness", DefaultValue = 1, MinValue = 1, MaxValue = 10, Group = "Visuals")]
        public int LineThickness { get; set; }

        [Parameter("Line Style", DefaultValue = LineStyle.LinesDots, Group = "Visuals")]
        public LineStyle LinesStyle { get; set; }

        [Parameter("Show Line Labels", DefaultValue = false, Group = "Visuals")]
        public bool ShowLineLabels { get; set; }

        [Parameter("Line Label Color", DefaultValue = "White", Group = "Visuals")]
        public Color LineLabelColor { get; set; }

        // === Notifications =========================================================
        [Parameter("Enable Notifications", DefaultValue = false, Group = "Notifications")]
        public bool EnableNotify { get; set; }

        [Parameter("Enable Native Alerts", DefaultValue = false, Group = "Notifications")]
        public bool EnableNativeAlerts { get; set; }

        [Parameter("Enable Sound Alerts", DefaultValue = false, Group = "Notifications")]
        public bool EnableSoundAlerts { get; set; }

        [Parameter("Sound Type", DefaultValue = SoundType.Announcement, Group = "Notifications")]
        public SoundType AlertSoundType { get; set; }

        [Parameter("Enable Email Alerts", DefaultValue = false, Group = "Notifications")]
        public bool EnableEmailAlerts { get; set; }

        [Parameter("Email Address", DefaultValue = "", Group = "Notifications")]
        public string EmailAddress { get; set; }

        [Parameter("Alert Delay (seconds)", DefaultValue = 5, MinValue = 0, Group = "Notifications")]
        public int AlertDelay { get; set; }

        // === Internal state ========================================================
        private enum LevelDirection { Up, Down }

        private int _effectiveInterval;
        private int _effectiveZoneWidth;
        private DateTime _lastNotificationTime;
        private double _multiplier;
        private double _prevLevel;
        private string _priceFormat;

        protected override void Initialize()
        {
            _multiplier = Math.Pow(10, Symbol.Digits);
            _priceFormat = "F" + Symbol.Digits;
            _lastNotificationTime = Server.Time;

            // --- Effective Interval (auto when input is 0) -------------------------
            if (Interval > 0)
            {
                _effectiveInterval = Interval;
            }
            else
            {
                double rangePoints = (Chart.TopY - Chart.BottomY) / Symbol.TickSize;
                double target = rangePoints / (2.0 * Math.Max(Levels, 1));
                _effectiveInterval = Math.Max(SnapToNice(target), 1);
                Print("RoundLevels: auto Interval = {0} points (visible range = {1:F0} points).", _effectiveInterval, rangePoints);
            }

            // --- Effective ZoneWidth (auto when input is 0) ------------------------
            if (ZoneWidth > 0)
            {
                _effectiveZoneWidth = ZoneWidth;
            }
            else
            {
                _effectiveZoneWidth = Math.Max(_effectiveInterval / 5, 1);
                Print("RoundLevels: auto ZoneWidth = {0} points.", _effectiveZoneWidth);
            }

            if (_effectiveZoneWidth >= _effectiveInterval)
            {
                Print("RoundLevels: ZoneWidth ({0}) must be less than Interval ({1}). Clamping.",
                    _effectiveZoneWidth, _effectiveInterval);
                _effectiveZoneWidth = Math.Max(_effectiveInterval - 1, 1);
            }
        }

        public override void Calculate(int index)
        {
            // Only react on the live bar — historical bars don't matter for current-price round levels.
            if (!IsLastBar) return;
            if (_effectiveInterval <= 0) return;

            double startingPrice = Symbol.Bid;
            double checkLevel = FindNextLevel(startingPrice, LevelDirection.Down);

            // When notifications are off, skip the redraw if the nearest round level hasn't shifted.
            // When they're on, we must run every tick so the in-zone check stays current.
            bool needsNotify = EnableNotify && (EnableNativeAlerts || EnableSoundAlerts || EnableEmailAlerts);
            if (!needsNotify && Math.Abs(checkLevel - _prevLevel) < Symbol.TickSize / 2.0) return;
            _prevLevel = checkLevel;

            for (int i = 0; i < Levels; i++)
            {
                double lvlDown = FindNextLevel(startingPrice - i * _effectiveInterval * Symbol.TickSize, LevelDirection.Down);
                double lvlUp = FindNextLevel(startingPrice + i * _effectiveInterval * Symbol.TickSize, LevelDirection.Up);

                double price1, price2;

                // --- Below current price -------------------------------------------
                string nameDn = ObjectPrefix + "_D" + i;
                if (InvertZones)
                {
                    price1 = lvlDown - (_effectiveZoneWidth / 2.0) * Symbol.TickSize;
                    price2 = lvlDown - (_effectiveInterval - _effectiveZoneWidth / 2.0) * Symbol.TickSize;
                }
                else
                {
                    price1 = lvlDown + (_effectiveZoneWidth / 2.0) * Symbol.TickSize;
                    price2 = lvlDown - (_effectiveZoneWidth / 2.0) * Symbol.TickSize;
                }
                DrawZone(nameDn, price1, price2, ColorDn);
                if (DrawLines) DrawLevelLine(ObjectPrefix + "_LD" + i, lvlDown);
                Notify(price1, price2);

                // --- Above current price -------------------------------------------
                string nameUp = ObjectPrefix + "_U" + i;
                if (InvertZones)
                {
                    price1 = lvlUp + (_effectiveInterval - _effectiveZoneWidth / 2.0) * Symbol.TickSize;
                    price2 = lvlUp + (_effectiveZoneWidth / 2.0) * Symbol.TickSize;
                }
                else
                {
                    price1 = lvlUp + (_effectiveZoneWidth / 2.0) * Symbol.TickSize;
                    price2 = lvlUp - (_effectiveZoneWidth / 2.0) * Symbol.TickSize;
                }
                DrawZone(nameUp, price1, price2, ColorUp);
                if (DrawLines) DrawLevelLine(ObjectPrefix + "_LU" + i, lvlUp);
                Notify(price1, price2);
            }

            // Center zone for inverted mode.
            if (InvertZones)
            {
                double lvlDown = FindNextLevel(startingPrice, LevelDirection.Down);
                double lvlUp = FindNextLevel(startingPrice, LevelDirection.Up);
                double price1 = lvlUp - (_effectiveZoneWidth / 2.0) * Symbol.TickSize;
                double price2 = lvlDown + (_effectiveZoneWidth / 2.0) * Symbol.TickSize;
                Color centerColor = Color.FromArgb(255,
                    (byte)((ColorDn.R + ColorUp.R) / 2),
                    (byte)((ColorDn.G + ColorUp.G) / 2),
                    (byte)((ColorDn.B + ColorUp.B) / 2));
                DrawZone(ObjectPrefix + "_C", price1, price2, centerColor);
                Notify(price1, price2);
            }
        }

        private double FindNextLevel(double sp, LevelDirection dir)
        {
            // 64-bit math here so high-priced symbols (BTC etc.) at high digit counts don't overflow.
            long integerPrice = (long)Math.Round(sp * _multiplier);
            int distance = (int)(integerPrice % _effectiveInterval);
            if (dir == LevelDirection.Down)
                return Math.Round((integerPrice - distance) / _multiplier, Symbol.Digits);
            else
                return Math.Round((integerPrice + (_effectiveInterval - distance)) / _multiplier, Symbol.Digits);
        }

        private void DrawZone(string name, double price1, double price2, Color baseColor)
        {
            // Span from the first loaded bar to a year past the last so the zone covers the whole visible chart, including the right margin.
            DateTime startTime = Bars.OpenTimes[0];
            DateTime endTime = Bars.OpenTimes.LastValue.AddYears(1);
            Color fillColor = Color.FromArgb((byte)ZoneOpacity, baseColor.R, baseColor.G, baseColor.B);
            ChartRectangle rect = Chart.DrawRectangle(name, startTime, price1, endTime, price2, fillColor);
            rect.IsFilled = true;
            rect.IsLocked = true;
        }

        private void DrawLevelLine(string name, double price)
        {
            ChartHorizontalLine line = Chart.DrawHorizontalLine(name, price, LineColor, LineThickness, LinesStyle);
            line.IsLocked = true;
            if (ShowLineLabels) DrawLineLabel(name + "_LL", price);
        }

        private void DrawLineLabel(string name, double price)
        {
            // Place at the last loaded bar; we redraw whenever levels shift, so the label moves with the chart's rightward edge.
            DateTime time = Bars.OpenTimes.LastValue;
            ChartText text = Chart.DrawText(name, " " + price.ToString(_priceFormat), time, price, LineLabelColor);
            text.HorizontalAlignment = HorizontalAlignment.Right;
            text.VerticalAlignment = VerticalAlignment.Center;
            text.IsLocked = true;
        }

        private void Notify(double price1, double price2)
        {
            if (!EnableNotify) return;
            if (!EnableNativeAlerts && !EnableSoundAlerts && !EnableEmailAlerts) return;
            if ((Server.Time - _lastNotificationTime).TotalSeconds < AlertDelay) return;

            double bid = Symbol.Bid;
            double hi = Math.Max(price1, price2);
            double lo = Math.Min(price1, price2);
            if (bid > hi || bid < lo) return;

            string text = string.Format("RoundLevels - {0} @ {1} - Bid Price ({2}) inside a Zone ({3}-{4})",
                Symbol.Name, TimeFrame, bid.ToString(_priceFormat), lo.ToString(_priceFormat), hi.ToString(_priceFormat));

            if (EnableNativeAlerts)
            {
                Notifications.ShowPopup("RoundLevels Alert", text, PopupNotificationState.Information);
                Print(text);
            }

            if (EnableSoundAlerts)
            {
                Notifications.PlaySound(AlertSoundType);
            }

            if (EnableEmailAlerts && !string.IsNullOrEmpty(EmailAddress))
            {
                string subject = string.Format("RoundLevels {0} Notification ({1})", Symbol.Name, TimeFrame);
                string body = string.Format("{0} - {1}\r\nRoundLevels Notification for {2} @ {3}\r\n{4}",
                    Account.BrokerName, Account.Number, Symbol.Name, TimeFrame, text);
                Notifications.SendEmail(EmailAddress, EmailAddress, subject, body);
            }

            _lastNotificationTime = Server.Time;
        }

        // Snap a positive number to the nearest value in the 1-2-5 sequence at the appropriate power of 10
        // (e.g. 33 -> 20, 70 -> 50, 150 -> 100). Geometric midpoints so each bucket covers an equal log-distance.
        private static int SnapToNice(double value)
        {
            if (value < 1) return 1;
            double magnitude = Math.Pow(10, Math.Floor(Math.Log10(value)));
            double normalized = value / magnitude;
            int nice;
            if (normalized < 1.414) nice = 1;       // sqrt(2)
            else if (normalized < 3.162) nice = 2;  // sqrt(10)
            else if (normalized < 7.071) nice = 5;  // sqrt(50)
            else nice = 10;
            return (int)(nice * magnitude);
        }
    }
}