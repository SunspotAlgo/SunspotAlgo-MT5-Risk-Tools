//+------------------------------------------------------------------+
//|                                    SunspotAlgo_MT5_Risk_Lock.mq5 |
//|                 SunspotAlgo 以损定仓下单面板 (开源跨平台版 v2.26) |
//| 官网: https://sunspotalgo.com/                                    |
//| Telegram 免费 4H 信号频道: https://t.me/SunspotSignal             |
//| TradingView 指标主页: https://www.tradingview.com/script/u7G1zSjA/|
//+------------------------------------------------------------------+
//--- 注意: link 属性不会单独显示, 它挂在「版权」文字上 —— 用户点击版权行即打开该网址
//--- 编译前请把 MetaEditor 的 CPU 架构设为 X64 Regular, 否则 Apple 芯片 Mac 会报 failed [568]
#property copyright "SunspotAlgo"
#property link      "https://sunspotalgo.com/"
#property version   "2.26"
#property description "SunspotAlgo MT5 以损定仓下单面板 (开源跨平台版 Windows / macOS)"
#property description "官网: https://sunspotalgo.com/"
#property description "Telegram 免费4H信号频道: https://t.me/SunspotSignal"
#property description "TradingView 指标页: https://www.tradingview.com/script/u7G1zSjA/"

#include <Trade\Trade.mqh>

CTrade trade;

// ======================= 跨平台适配参数 =======================
enum ENUM_UI_FONTSET {
    FONTSET_WINDOWS = 0,   // Windows (微软雅黑)
    FONTSET_MACOS   = 1,   // macOS / Wine (Arial Unicode MS)
    FONTSET_CUSTOM  = 2    // 自定义 (在下方三个字体参数里填写)
};

input group "=== Z. 跨平台界面适配 (Mac 用户只需改这一组) ==="
input ENUM_UI_FONTSET Inp_FontSet       = FONTSET_WINDOWS; // 界面字体方案 [Mac 请选 macOS]
input string  Inp_Font_CN_Custom        = "";              // 自定义中文字体 (仅选"自定义"时生效)
input string  Inp_Font_Bold_Custom      = "";              // 自定义粗体字体 (留空则用中文字体)
input string  Inp_Font_EN_Custom        = "";              // 自定义数字字体 (留空则用中文字体)
input double  Inp_UIScale               = 0.0;             // 面板几何缩放 [0=按DPI自动; 一般不用改]
input int     Inp_DpiCap                = 144;             // 几何缩放的DPI上限 [防止 Retina 面板过大]
input double  Inp_FontScale             = 1.0;             // 全局字号微调 [1.0=标准; Mac 文字仍偏大填0.9, 偏小填1.1]
input bool    Inp_AutoFitFont           = true;            // 文字超出框宽时自动缩小字号 [建议保持开启]
input bool    Inp_EnableSound           = true;            // 交易音效 [Wine 下音频异常时可关闭]

// --- 面板状态全局变量 ---
double  g_RiskAmount = 100.0;
bool    g_IsBuy      = true;  

// 模式: 0=市价执行, 1=挂单埋伏, 2=回撤挂单
int     g_OrderMode  = 0;     
double  g_DrawdownPct= 0.15;  

double  g_EntryPrice = 0.0;
double  g_SLPrice    = 0.0;

double  g_CalcLots   = 0.0;
double  g_ActualRisk = 0.0;
string  g_WarningMsg = "";    

// --- UI 全局与缩放变量 ---
const string PFX = "SZR_";    
double g_Scale   = 1.0;       // 面板"几何"(像素坐标)缩放 —— 必须自己乘
double g_OsScale = 1.0;       // 终端对"点"为单位字号的自动缩放 —— 不能重复乘
string g_FontCN   = "Microsoft YaHei UI";
string g_FontBold = "Microsoft YaHei UI Bold";
string g_FontEN   = "Consolas";
int g_PanelX = 30;            
int g_PanelY = 40;            
bool g_IsDragging = false;
int g_DragOffsetX = 0;
int g_DragOffsetY = 0;
string g_Currency = "USD";    

// --- 布局派生尺寸 (DrawPanel 里按缩放算出, UpdateUI 里做动态文案适配时复用) ---
int g_InnerW     = 0;         // 面板内可用宽度
int g_PctBtnW    = 0;         // 百分比按钮宽
int g_PctBtnH    = 0;         // 百分比按钮高
int g_LblPctMaxW = 0;         // "回撤比例:" 标签可用宽度
int g_EditMaxW   = 0;         // 输入框内可用宽度
int g_EditMaxH   = 0;         // 输入框内可用高度

// --- UI 尺寸基准 ---
const int BASE_W = 310;       
const int BASE_H = 552;       
const int HEAD_H = 50;        

// --- 高级现代配色方案 ---
const color C_BG_HEAD   = C'25,30,35'; 
const color C_BG_BODY   = C'32,36,40'; 
const color C_BG_CARD   = C'42,48,55'; 
const color C_BORDER    = C'55,60,65'; 
const color C_INP_BG    = C'20,25,30'; 
const color C_INP_DIS   = C'35,40,45'; 
const color C_TXT_HEAD  = clrGold;     
const color C_TXT_SYM   = clrSkyBlue;  
const color C_TXT_SUB   = C'130,140,150';
const color C_TXT_LBL   = C'160,165,170';
const color C_TXT_VAL   = clrWhite;    
const color C_BTN_OFF   = C'50,55,60'; 
const color C_BTN_ON    = clrDodgerBlue;
const color C_BTN_SUB   = C'40,160,100';
const color C_WARN      = clrOrangeRed;
const color C_LOTS_HL   = clrAqua;     

//+------------------------------------------------------------------+
//| 几何缩放: 只用于像素坐标/尺寸 (OBJPROP_XDISTANCE / XSIZE ...)     |
int S(int value) { return (int)MathRound(value * g_Scale); }

//+------------------------------------------------------------------+
//| 字号换算 —— 本面板最关键的跨平台修正                              |
//|                                                                  |
//| MQL5 的字号单位是"点", 终端/操作系统会按屏幕 DPI 自动把它换算成   |
//| 像素 (官方文档: 负值以 1/10 点为单位时"取决于系统缩放设置"),      |
//| 而 OBJPROP_XDISTANCE 这类像素坐标【不会】被自动缩放。             |
//|                                                                  |
//| 因此字号不能再乘一遍 g_Scale, 否则在 DPI>96 的机器上会二次放大    |
//| (macOS Retina 上实测约放大 3 倍, 而面板几何只有 1.5 倍 -> 文字满天飞)。|
//| 正确做法: 先把终端将要施加的系统缩放除掉, 再乘我们想要的几何比例。|
//| DPI=96 时 F(n) == n, Windows 端行为与旧版完全一致。               |
//+------------------------------------------------------------------+
int F(int basePt) {
    double v = basePt * g_Scale / g_OsScale * Inp_FontScale;
    int pt = (int)MathRound(v);
    if(pt < 6) pt = 6;
    return pt;
}

//--- 系统字号缩放系数 = 实际 DPI / 96 (不设上限, 用于把终端那层缩放抵消掉)
double ResolveOsScale() {
    int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
    if(dpi <= 0)   dpi = 96;
    if(dpi > 384)  dpi = 384;
    return dpi / 96.0;
}

//+------------------------------------------------------------------+
//| 自动收缩: 按终端真实的字体度量测量, 文字超出可用框就逐点调小字号  |
//| (只缩不放, 下限 6pt)。不同平台字体宽度不同时这是最后一道保险。    |
//+------------------------------------------------------------------+
int FitPt(string text, string fontName, bool bold, int basePt, int maxW, int maxH) {
    int pt = F(basePt);
    if(!Inp_AutoFitFont || (maxW <= 0 && maxH <= 0) || StringLen(text) == 0) return pt;

    uint flags = bold ? FW_BOLD : FW_NORMAL;
    for(int i = 0; i < 16 && pt > 6; i++) {
        if(!TextSetFont(fontName, -pt * 10, flags)) return F(basePt); // 字体不可用, 保持原字号
        uint w = 0, h = 0;
        if(!TextGetSize(text, w, h)) return F(basePt);
        if((maxW <= 0 || (int)w <= maxW) && (maxH <= 0 || (int)h <= maxH)) return pt;
        pt--;
    }
    return pt;
}

//--- 字体方案解析: Windows / macOS / 自定义
void ResolveUIStyle() {
    if(Inp_FontSet == FONTSET_MACOS) {
        // macOS 自带 Arial Unicode MS (含完整中日韩字形), Wine 封装环境下最稳
        g_FontCN   = "Arial Unicode MS";
        g_FontBold = "Arial Unicode MS";
        g_FontEN   = "Arial Unicode MS";
    } else if(Inp_FontSet == FONTSET_CUSTOM) {
        g_FontCN   = (StringLen(Inp_Font_CN_Custom)   > 0) ? Inp_Font_CN_Custom   : "Microsoft YaHei UI";
        g_FontBold = (StringLen(Inp_Font_Bold_Custom) > 0) ? Inp_Font_Bold_Custom : g_FontCN;
        g_FontEN   = (StringLen(Inp_Font_EN_Custom)   > 0) ? Inp_Font_EN_Custom   : g_FontCN;
    } else {
        g_FontCN   = "Microsoft YaHei UI";
        g_FontBold = "Microsoft YaHei UI Bold";
        g_FontEN   = "Consolas";
    }
}

//--- 缩放解析: 手动值优先, 否则按屏幕 DPI 自动 (带上限, 防止 Retina 下放大过度)
double ResolveScale() {
    if(Inp_UIScale > 0.0) return Inp_UIScale;
    int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
    if(dpi <= 0) dpi = 96;
    int cap = (Inp_DpiCap >= 96) ? Inp_DpiCap : 96;
    if(dpi > cap) dpi = cap;
    return dpi / 96.0;
}

//--- 数值输入容错: 兼容小数点用逗号的区域设置, 以及粘贴时带进来的空格
double ParseNum(string s) {
    StringReplace(s, " ", "");
    StringReplace(s, ",", ".");
    return StringToDouble(s);
}

//--- 音效开关包装 (Wine/macOS 下音频子系统异常时可整体关掉)
void PlayAlert(string snd) { if(Inp_EnableSound) PlaySound(snd); }

//+------------------------------------------------------------------+
int OnInit() {
    trade.SetExpertMagicNumber(888999);
    trade.SetAsyncMode(false);
    
    ResolveUIStyle();
    g_Scale   = ResolveScale();
    g_OsScale = ResolveOsScale();
    g_Currency = AccountInfoString(ACCOUNT_CURRENCY);
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
    
    DrawPanel();
    EventSetMillisecondTimer(200);
    Print("[SunspotAlgo] MT5 以损定仓下单面板已加载 | 官网: https://sunspotalgo.com/ | Telegram 免费4H信号频道: https://t.me/SunspotSignal | TradingView: https://www.tradingview.com/script/u7G1zSjA/");
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    EventKillTimer();
    ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
    ObjectsDeleteAll(0, PFX);
    ChartRedraw();
}

void OnTick() {}

void OnTimer() {
    ReadInputsAndCalculate();
    UpdateUI();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
    if(id == CHARTEVENT_MOUSE_MOVE) {
        int x = (int)lparam, y = (int)dparam, mouseState = (int)StringToInteger(sparam);
        if(mouseState == 1) { 
            if(!g_IsDragging) {
                int hX = (int)ObjectGetInteger(0, PFX+"BG_HEAD", OBJPROP_XDISTANCE);
                int hY = (int)ObjectGetInteger(0, PFX+"BG_HEAD", OBJPROP_YDISTANCE);
                int hW = (int)ObjectGetInteger(0, PFX+"BG_HEAD", OBJPROP_XSIZE);
                int hH = (int)ObjectGetInteger(0, PFX+"BG_HEAD", OBJPROP_YSIZE);
                if(x >= hX && x <= hX + hW && y >= hY && y <= hY + hH) {
                    g_IsDragging = true;
                    g_DragOffsetX = x - g_PanelX;
                    g_DragOffsetY = y - g_PanelY;
                }
            } else { MovePanel(x - g_DragOffsetX, y - g_DragOffsetY); }
        } else { g_IsDragging = false; }
    }

    if(id == CHARTEVENT_OBJECT_CLICK) {
        if(sparam == PFX+"BTN_DIR_BUY") { g_IsBuy = true; }
        if(sparam == PFX+"BTN_DIR_SELL") { g_IsBuy = false; }
        
        if(sparam == PFX+"BTN_MOD_MKT") { g_OrderMode = 0; }
        if(sparam == PFX+"BTN_MOD_LMT") { g_OrderMode = 1; }
        if(sparam == PFX+"BTN_MOD_DD")  { g_OrderMode = 2; }
        
        if(sparam == PFX+"BTN_PCT_15")  { g_DrawdownPct = 0.15; }
        if(sparam == PFX+"BTN_PCT_25")  { g_DrawdownPct = 0.25; }
        if(sparam == PFX+"BTN_PCT_35")  { g_DrawdownPct = 0.35; }
        if(sparam == PFX+"BTN_PCT_50")  { g_DrawdownPct = 0.50; }
        
        if(sparam == PFX+"BTN_SUBMIT") { ExecuteOrder(); }
        ChartRedraw();
    }
    
    if(id == CHARTEVENT_OBJECT_ENDEDIT) {
        ReadInputsAndCalculate();
        ChartRedraw();
    }
}

void MovePanel(int newX, int newY) {
    int dx = newX - g_PanelX, dy = newY - g_PanelY;
    for(int i = ObjectsTotal(0) - 1; i >= 0; i--) {
        string name = ObjectName(0, i);
        if(StringFind(name, PFX) == 0) {
            ObjectSetInteger(0, name, OBJPROP_XDISTANCE, (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE) + dx);
            ObjectSetInteger(0, name, OBJPROP_YDISTANCE, (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE) + dy);
        }
    }
    g_PanelX = newX; g_PanelY = newY;
    ChartRedraw();
}

void ReadInputsAndCalculate() {
    g_WarningMsg = ""; g_CalcLots = 0; g_ActualRisk = 0;

    string rStr = ObjectGetString(0, PFX+"INP_RISK", OBJPROP_TEXT);
    if(rStr != "") g_RiskAmount = ParseNum(rStr);
    
    string slStr = ObjectGetString(0, PFX+"INP_SL", OBJPROP_TEXT);
    if(slStr != "") g_SLPrice = ParseNum(slStr);
    else g_SLPrice = 0.0;

    string sym = Symbol();
    double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
    double bid = SymbolInfoDouble(sym, SYMBOL_BID);
    double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
    double minVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
    double maxVol = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);

    if(g_OrderMode == 0) {
        g_EntryPrice = g_IsBuy ? ask : bid;
        if(g_SLPrice <= 0) { g_WarningMsg = "等待输入止损价"; return; }
    } else if(g_OrderMode == 1) {
        string enStr = ObjectGetString(0, PFX+"INP_ENTRY", OBJPROP_TEXT);
        g_EntryPrice = ParseNum(enStr);
        if(g_EntryPrice <= 0) { g_WarningMsg = "等待输入挂单价"; return; }
        if(g_SLPrice <= 0) { g_WarningMsg = "等待输入止损价"; return; }
    } else if(g_OrderMode == 2) {
        if(g_SLPrice <= 0) { g_WarningMsg = "需输入止损以计算回撤"; return; }
        double currentPrice = g_IsBuy ? ask : bid;
        if((g_IsBuy && g_SLPrice >= currentPrice) || (!g_IsBuy && g_SLPrice <= currentPrice)) { 
            g_WarningMsg = "止损价与现价方向冲突"; return; 
        }
        double riskSpace = MathAbs(currentPrice - g_SLPrice);
        double drawdownDist = riskSpace * g_DrawdownPct;
        if(g_IsBuy) g_EntryPrice = currentPrice - drawdownDist;
        else        g_EntryPrice = currentPrice + drawdownDist;
    }

    if(g_IsBuy && g_SLPrice >= g_EntryPrice) { g_WarningMsg = "多单止损需低于入场价"; return; }
    if(!g_IsBuy && g_SLPrice <= g_EntryPrice) { g_WarningMsg = "空单止损需高于入场价"; return; }

    double lossPerLot = 0;
    ENUM_ORDER_TYPE testType = g_IsBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    if(!OrderCalcProfit(testType, sym, 1.0, g_EntryPrice, g_SLPrice, lossPerLot)) {
        g_WarningMsg = "利润测算失败"; return;
    }
    lossPerLot = MathAbs(lossPerLot);
    if(lossPerLot <= 0.0001) { g_WarningMsg = "点差或参数异常"; return; }

    double minLoss = minVol * lossPerLot;
    if(minLoss > g_RiskAmount) {
        g_WarningMsg = StringFormat("风险金不足, 最小需 %s", DoubleToString(minLoss, 2)); return;
    }

    double rawLots = g_RiskAmount / lossPerLot;
    double targetLots = MathFloor(rawLots / step) * step;
    
    if(targetLots < minVol) targetLots = minVol; 
    if(targetLots > maxVol) targetLots = maxVol;

    g_CalcLots = NormalizeDouble(targetLots, 2);
    g_ActualRisk = g_CalcLots * lossPerLot;
}

//+------------------------------------------------------------------+
//| 执行下单模块 (新增 3R 止盈自动计算逻辑)                          |
//+------------------------------------------------------------------+
void ExecuteOrder() {
    if(g_CalcLots <= 0 || g_WarningMsg != "") return;

    string sym = Symbol();
    double reqMargin = 0;
    ENUM_ORDER_TYPE oType;
    double currentAsk = SymbolInfoDouble(sym, SYMBOL_ASK);
    double currentBid = SymbolInfoDouble(sym, SYMBOL_BID);

    if(g_OrderMode == 0) {
        oType = g_IsBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    } else {
        if(g_IsBuy) oType = (g_EntryPrice < currentAsk) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
        else        oType = (g_EntryPrice > currentBid) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;
    }

    if(!OrderCalcMargin(oType, sym, g_CalcLots, g_EntryPrice, reqMargin)) { g_WarningMsg = "保证金测算失败"; return; }
    if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < reqMargin) { g_WarningMsg = "可用保证金不足"; return; }

    // 【新增核心逻辑】自动计算 5R 止盈价 (隐式不显示)
    // 逻辑：多空通用公式，(入场价 - 止损价) 即为 1R 带方向的距离。
    double tpPrice = g_EntryPrice + (g_EntryPrice - g_SLPrice) * 3.0; 
    
    // 将 TP 价格格式化为当前品种的小数点精度，防止服务器拒单
    int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
    tpPrice = NormalizeDouble(tpPrice, digits);

    string comment = "SunspotRisk_" + DoubleToString(g_ActualRisk, 2);
    bool res = false;

    // 将原有的 tp 传参 0 替换为了我们计算出的 tpPrice
    if(g_OrderMode == 0) {
        res = g_IsBuy ? trade.Buy(g_CalcLots, sym, 0, g_SLPrice, tpPrice, comment) 
                      : trade.Sell(g_CalcLots, sym, 0, g_SLPrice, tpPrice, comment);
    } else {
        res = trade.OrderOpen(sym, oType, g_CalcLots, 0.0, g_EntryPrice, g_SLPrice, tpPrice, ORDER_TIME_GTC, 0, comment);
    }

    if(res && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED)) {
        PlayAlert("Ok.wav");
        ObjectSetString(0, PFX+"INP_SL", OBJPROP_TEXT, "");
        if(g_OrderMode == 1) ObjectSetString(0, PFX+"INP_ENTRY", OBJPROP_TEXT, "");
    } else {
        g_WarningMsg = "交易拒绝: " + IntegerToString(trade.ResultRetcode());
        PlayAlert("timeout.wav");
    }
}

void UpdateUI() {
    ObjectSetInteger(0, PFX+"BTN_DIR_BUY", OBJPROP_BGCOLOR, g_IsBuy ? C_BTN_ON : C_BTN_OFF);
    ObjectSetInteger(0, PFX+"BTN_DIR_SELL", OBJPROP_BGCOLOR, !g_IsBuy ? C_BTN_ON : C_BTN_OFF);
    ObjectSetInteger(0, PFX+"BTN_DIR_BUY", OBJPROP_COLOR, g_IsBuy ? clrWhite : clrGray);
    ObjectSetInteger(0, PFX+"BTN_DIR_SELL", OBJPROP_COLOR, !g_IsBuy ? clrWhite : clrGray);
    ObjectSetInteger(0, PFX+"BTN_DIR_BUY", OBJPROP_STATE, g_IsBuy);
    ObjectSetInteger(0, PFX+"BTN_DIR_SELL", OBJPROP_STATE, !g_IsBuy);
    
    ObjectSetInteger(0, PFX+"BTN_MOD_MKT", OBJPROP_BGCOLOR, g_OrderMode==0 ? C_BTN_ON : C_BTN_OFF);
    ObjectSetInteger(0, PFX+"BTN_MOD_LMT", OBJPROP_BGCOLOR, g_OrderMode==1 ? C_BTN_ON : C_BTN_OFF);
    ObjectSetInteger(0, PFX+"BTN_MOD_DD",  OBJPROP_BGCOLOR, g_OrderMode==2 ? C_BTN_ON : C_BTN_OFF);
    ObjectSetInteger(0, PFX+"BTN_MOD_MKT", OBJPROP_COLOR, g_OrderMode==0 ? clrWhite : clrGray);
    ObjectSetInteger(0, PFX+"BTN_MOD_LMT", OBJPROP_COLOR, g_OrderMode==1 ? clrWhite : clrGray);
    ObjectSetInteger(0, PFX+"BTN_MOD_DD",  OBJPROP_COLOR, g_OrderMode==2 ? clrWhite : clrGray);
    ObjectSetInteger(0, PFX+"BTN_MOD_MKT", OBJPROP_STATE, g_OrderMode==0);
    ObjectSetInteger(0, PFX+"BTN_MOD_LMT", OBJPROP_STATE, g_OrderMode==1);
    ObjectSetInteger(0, PFX+"BTN_MOD_DD",  OBJPROP_STATE, g_OrderMode==2);

    bool isDD = (g_OrderMode == 2);
    // 动态文案: 改字必须同时重算字号, 否则长文案会溢出方框
    int pctMaxW = g_PctBtnW - S(10);
    int pctMaxH = g_PctBtnH - S(6);
    RefitObj(PFX+"LBL_PCT",    isDD ? "回撤比例:" : " ", g_FontCN, false, 9, g_LblPctMaxW, S(20)-S(6));
    RefitObj(PFX+"BTN_PCT_15", isDD ? "15%" : " ", g_FontCN, true, 9, pctMaxW, pctMaxH);
    RefitObj(PFX+"BTN_PCT_25", isDD ? "25%" : " ", g_FontCN, true, 9, pctMaxW, pctMaxH);
    RefitObj(PFX+"BTN_PCT_35", isDD ? "35%" : " ", g_FontCN, true, 9, pctMaxW, pctMaxH);
    RefitObj(PFX+"BTN_PCT_50", isDD ? "50%" : " ", g_FontCN, true, 9, pctMaxW, pctMaxH);
    
    ObjectSetInteger(0, PFX+"BTN_PCT_15", OBJPROP_BGCOLOR, !isDD ? C_BG_CARD : (g_DrawdownPct==0.15 ? clrOrange : C_BTN_OFF));
    ObjectSetInteger(0, PFX+"BTN_PCT_25", OBJPROP_BGCOLOR, !isDD ? C_BG_CARD : (g_DrawdownPct==0.25 ? clrOrange : C_BTN_OFF));
    ObjectSetInteger(0, PFX+"BTN_PCT_35", OBJPROP_BGCOLOR, !isDD ? C_BG_CARD : (g_DrawdownPct==0.35 ? clrOrange : C_BTN_OFF));
    ObjectSetInteger(0, PFX+"BTN_PCT_50", OBJPROP_BGCOLOR, !isDD ? C_BG_CARD : (g_DrawdownPct==0.50 ? clrOrange : C_BTN_OFF));
    
    ObjectSetInteger(0, PFX+"BTN_PCT_15", OBJPROP_STATE, isDD && g_DrawdownPct==0.15);
    ObjectSetInteger(0, PFX+"BTN_PCT_25", OBJPROP_STATE, isDD && g_DrawdownPct==0.25);
    ObjectSetInteger(0, PFX+"BTN_PCT_35", OBJPROP_STATE, isDD && g_DrawdownPct==0.35);
    ObjectSetInteger(0, PFX+"BTN_PCT_50", OBJPROP_STATE, isDD && g_DrawdownPct==0.50);

    if(g_OrderMode == 0) {
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_READONLY, true);
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_BGCOLOR, C_INP_DIS);
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_COLOR, clrDimGray);
        RefitObj(PFX+"INP_ENTRY", "现价执行", g_FontEN, false, 11, g_EditMaxW, g_EditMaxH);
        
    } else if(g_OrderMode == 1) {
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_READONLY, false);
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_BGCOLOR, C_INP_BG);
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_COLOR, C_TXT_VAL);
        string curTxt = ObjectGetString(0, PFX+"INP_ENTRY", OBJPROP_TEXT);
        if(curTxt == "现价执行" || curTxt == "等待止损...") RefitObj(PFX+"INP_ENTRY", "", g_FontEN, false, 11, g_EditMaxW, g_EditMaxH);
        
    } else if(g_OrderMode == 2) {
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_READONLY, true);
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_BGCOLOR, C_INP_DIS);
        ObjectSetInteger(0, PFX+"INP_ENTRY", OBJPROP_COLOR, clrGold); 
        string entryTxt;
        if(g_SLPrice > 0 && g_WarningMsg == "")
            entryTxt = DoubleToString(g_EntryPrice, (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS));
        else
            entryTxt = "等待止损...";
        RefitObj(PFX+"INP_ENTRY", entryTxt, g_FontEN, false, 11, g_EditMaxW, g_EditMaxH);
    }

    if(g_WarningMsg != "") {
        RefitObj(PFX+"LBL_LOTS_VAL", "---", g_FontBold, true, 30, g_InnerW, S(40));
        ObjectSetInteger(0, PFX+"LBL_LOTS_VAL", OBJPROP_COLOR, C_TXT_LBL);
        RefitObj(PFX+"LBL_RISK_VAL", g_WarningMsg, g_FontCN, false, 9, g_InnerW, 0);
        ObjectSetInteger(0, PFX+"LBL_RISK_VAL", OBJPROP_COLOR, C_WARN);
    } else {
        RefitObj(PFX+"LBL_LOTS_VAL", DoubleToString(g_CalcLots, 2), g_FontBold, true, 30, g_InnerW, S(40));
        ObjectSetInteger(0, PFX+"LBL_LOTS_VAL", OBJPROP_COLOR, C_LOTS_HL);
        string riskText = StringFormat("最大承损: %.2f %s", g_ActualRisk, g_Currency);
        RefitObj(PFX+"LBL_RISK_VAL", riskText, g_FontCN, false, 9, g_InnerW, 0);
        ObjectSetInteger(0, PFX+"LBL_RISK_VAL", OBJPROP_COLOR, clrGray);
    }
    
    ChartRedraw();
}

void DrawPanel() {
    int x = g_PanelX, y = g_PanelY;
    
    CreateRect(PFX+"BG_BORDER", x-S(1), y-S(1), S(BASE_W+2), S(BASE_H+2), C_BORDER);
    CreateRect(PFX+"BG_HEAD", x, y, S(BASE_W), S(HEAD_H), C_BG_HEAD);
    CreateRect(PFX+"BG_BODY", x, y+S(HEAD_H), S(BASE_W), S(BASE_H-HEAD_H), C_BG_BODY);

    // 注意: 下面所有字号参数都是"基准点值"(为 96 DPI 设计的原始值),
    // 不再乘 S()。真正的换算交给 F() / FitPt(), 否则会用 DPI 缩放两次。
    g_InnerW = S(BASE_W) - S(20);
    CreateLabel(PFX+"TITLE", x+S(BASE_W)/2, y+S(6), "SunspotAlgo 以损定仓", 11, C_TXT_HEAD, true, ALIGN_CENTER, g_InnerW);
    CreateLabel(PFX+"SYMBOL", x+S(BASE_W)/2, y+S(28), "当前品种: " + Symbol(), 9, C_TXT_SYM, false, ALIGN_CENTER, g_InnerW);

    int curY = y + S(HEAD_H) + S(15);
    int editX = x + S(145);
    int lblMaxW = S(145 - 25 - 6);
    g_EditMaxW = S(140) - S(10);
    g_EditMaxH = S(26) - S(6);
    
    CreateLabel(PFX+"LBL_RISK", x+S(25), curY+S(4), "预期风险 ("+g_Currency+"):", 10, C_TXT_LBL, false, ALIGN_LEFT, lblMaxW);
    CreateEdit(PFX+"INP_RISK", editX, curY, S(140), S(26), DoubleToString(g_RiskAmount, 0));

    // ==========================================
    curY += S(40);
    int card1_H = S(65);
    int cardPadX = S(15);
    int cardW = S(BASE_W) - cardPadX * 2;
    
    CreateRect(PFX+"CARD_DIR_BG", x+cardPadX, curY, cardW, card1_H, C_BG_CARD);
    CreateLabel(PFX+"SUB_DIR", x+cardPadX+S(10), curY+S(6), "▍ 交易方向", 9, C_TXT_SUB, true, ALIGN_LEFT, cardW - S(20));
    
    int btnDirY = curY + S(28);
    int btnDirW = (cardW - S(30)) / 2; 
    CreateButton(PFX+"BTN_DIR_BUY",  x+cardPadX+S(10), btnDirY, btnDirW, S(26), "做 多 (Long)", C_BTN_ON, clrWhite, true);
    CreateButton(PFX+"BTN_DIR_SELL", x+cardPadX+S(20)+btnDirW, btnDirY, btnDirW, S(26), "做 空 (Short)", C_BTN_OFF, clrGray, true);

    // ==========================================
    curY += card1_H + S(10);
    int card2_H = S(95); 
    
    CreateRect(PFX+"CARD_MOD_BG", x+cardPadX, curY, cardW, card2_H, C_BG_CARD);
    CreateLabel(PFX+"SUB_MOD", x+cardPadX+S(10), curY+S(6), "▍ 订单执行模式", 9, C_TXT_SUB, true, ALIGN_LEFT, cardW - S(20));
    
    int btnModY = curY + S(28);
    int btnModW = (cardW - S(40)) / 3; 
    CreateButton(PFX+"BTN_MOD_MKT", x+cardPadX+S(10), btnModY, btnModW, S(26), "市价执行", C_BTN_ON, clrWhite, true);
    CreateButton(PFX+"BTN_MOD_LMT", x+cardPadX+S(20)+btnModW, btnModY, btnModW, S(26), "挂单埋伏", C_BTN_OFF, clrGray, true);
    CreateButton(PFX+"BTN_MOD_DD",  x+cardPadX+S(30)+btnModW*2, btnModY, btnModW, S(26), "回撤挂单", C_BTN_OFF, clrGray, true);

    int pctY = btnModY + S(34);
    g_PctBtnW = S(36);
    g_PctBtnH = S(20);
    int pctGap = S(4);  
    int totalPctW = g_PctBtnW * 4 + pctGap * 3;
    int pctStartX = x + cardPadX + cardW - totalPctW - S(10); 
    g_LblPctMaxW = pctStartX - (x + cardPadX + S(10)) - S(4);
    if(g_LblPctMaxW < 0) g_LblPctMaxW = 0;

    CreateLabel(PFX+"LBL_PCT", x+cardPadX+S(10), pctY+S(4), " ", 9, clrOrange, false, ALIGN_LEFT, g_LblPctMaxW); 
    
    // 百分比按钮初始文本是空格, 用最长的 "50%" 作为测量基准, 防止动态文案溢出
    CreateButton(PFX+"BTN_PCT_15", pctStartX, pctY, g_PctBtnW, g_PctBtnH, " ", C_BG_CARD, clrWhite, true, "50%");
    CreateButton(PFX+"BTN_PCT_25", pctStartX + g_PctBtnW + pctGap, pctY, g_PctBtnW, g_PctBtnH, " ", C_BG_CARD, clrWhite, true, "50%");
    CreateButton(PFX+"BTN_PCT_35", pctStartX + (g_PctBtnW + pctGap)*2, pctY, g_PctBtnW, g_PctBtnH, " ", C_BG_CARD, clrWhite, true, "50%");
    CreateButton(PFX+"BTN_PCT_50", pctStartX + (g_PctBtnW + pctGap)*3, pctY, g_PctBtnW, g_PctBtnH, " ", C_BG_CARD, clrWhite, true, "50%");

    // ==========================================
    curY += card2_H + S(15);
    
    CreateLabel(PFX+"LBL_ENTRY", x+S(25), curY+S(4), "入场价格:", 10, C_TXT_LBL, false, ALIGN_LEFT, lblMaxW);
    CreateEdit(PFX+"INP_ENTRY", editX, curY, S(140), S(26), ""); 
    
    curY += S(35);
    CreateLabel(PFX+"LBL_SL", x+S(25), curY+S(4), "止损价格:", 10, clrOrange, false, ALIGN_LEFT, lblMaxW);
    CreateEdit(PFX+"INP_SL", editX, curY, S(140), S(26), "");

    curY += S(45);
    CreateLabel(PFX+"LBL_LOTS_TITLE", x+S(BASE_W)/2, curY, "计算开仓手数 (Lots)", 9, C_TXT_LBL, false, ALIGN_CENTER, g_InnerW);
    CreateLabel(PFX+"LBL_LOTS_VAL", x+S(BASE_W)/2, curY+S(18), "---", 30, C_TXT_LBL, true, ALIGN_CENTER, g_InnerW, S(40)); 
    CreateLabel(PFX+"LBL_RISK_VAL", x+S(BASE_W)/2, curY+S(62), "等待输入止损...", 9, clrDimGray, false, ALIGN_CENTER, g_InnerW);

    curY += S(85);
    CreateButton(PFX+"BTN_SUBMIT", x+S(20), curY, S(BASE_W-40), S(38), "确 认 发 送 (SEND)", C_BTN_SUB, clrWhite, true);
    CreateLabel(PFX+"BRAND_FOOTER", x+S(BASE_W)/2, curY+S(44), "sunspotalgo.com | TG: @SunspotSignal", 7, C_TXT_SUB, false, ALIGN_CENTER, g_InnerW);
    
    UpdateUI();
}

void CreateLabel(string name, int x, int y, string text, int size, color clr, bool bold=false, ENUM_ALIGN_MODE align=ALIGN_LEFT, int maxW=0, int maxH=0) {
    string fnt = bold ? g_FontBold : g_FontCN;
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetString(0, name, OBJPROP_FONT, fnt);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FitPt(text, fnt, bold, size, maxW, maxH));
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_ALIGN, align);
    if(align == ALIGN_CENTER) ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
    else if(align == ALIGN_RIGHT) ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
    else ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
}

void CreateRect(string name, int x, int y, int w, int h, color bg) {
    ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void CreateEdit(string name, int x, int y, int w, int h, string text) {
    ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, C_INP_BG); ObjectSetInteger(0, name, OBJPROP_COLOR, C_TXT_VAL);
    ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER); ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetString(0, name, OBJPROP_FONT, g_FontEN);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FitPt(text, g_FontEN, false, 11, w - S(10), h - S(6)));
}

void CreateButton(string name, int x, int y, int w, int h, string text, color bg, color txtColor, bool bold=false, string fitRef="") {
    string fnt = bold ? g_FontBold : g_FontCN;
    string ref = (StringLen(fitRef) > 0) ? fitRef : text;
    ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w); ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, name, OBJPROP_COLOR, txtColor);
    ObjectSetString(0, name, OBJPROP_FONT, fnt);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FitPt(ref, fnt, bold, 9, w - S(10), h - S(6)));
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER); 
    ObjectSetInteger(0, name, OBJPROP_STATE, false); 
}

//+------------------------------------------------------------------+
//| 动态文案改字后必须重新适配字号, 否则长文案(警告语/价格)会溢出框   |
//| 只在真的需要变化时才写属性, 避免定时器每 200ms 触发一次无谓重设    |
//+------------------------------------------------------------------+
void RefitObj(string name, string text, string fontName, bool bold, int basePt, int maxW, int maxH=0) {
    if(ObjectGetString(0, name, OBJPROP_TEXT) != text)
        ObjectSetString(0, name, OBJPROP_TEXT, text);
    int pt = FitPt(text, fontName, bold, basePt, maxW, maxH);
    if((int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE) != pt)
        ObjectSetInteger(0, name, OBJPROP_FONTSIZE, pt);
}
//+------------------------------------------------------------------+
