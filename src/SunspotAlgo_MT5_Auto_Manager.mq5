//+------------------------------------------------------------------+
//|                                 SunspotAlgo_MT5_Auto_Manager.mq5 |
//|                SunspotAlgo 自动仓位管理系统 (开源跨平台版 V4.33)  |
//| 官网: https://sunspotalgo.com/                                    |
//| Telegram 免费 4H 信号频道: https://t.me/SunspotSignal             |
//| TradingView 指标主页: https://www.tradingview.com/script/u7G1zSjA/|
//| 核心更新: 面板右上角增加第三行显示[以损定仓]模块详情               |
//| V4.32 修正: 「追踪止盈」列文案改为严格按"实际开启的模块"推导下一步    |
//|   关闭保本 + 开启追踪 时, 不再错误显示"等待保本", 而是"等待追踪"     |
//|   「智能状态」列不再在保本模块关闭时误报"已保本"                    |
//|   追踪激活后, 直接显示当前真正锁定的止损 R 值 (锁X.XXR)             |
//| V4.33 修正: 坏报价防线 —— 品种未订阅时 BID/ASK 为 0, 空单的浮盈会被   |
//|   算成"入场价÷止损距离", 让"最高R"变成 346 这种天文数字 (且只增不减)  |
//|   1) 取价前先 SymbolSelect, 并校验 bid/ask > 0                  |
//|   2) R 超出合理范围(MAX_SANE_R)的样本直接丢弃, 不更新最高值          |
//|   3) 硬止盈需连续确认, 单次坏样本不再能平掉整仓                     |
//|   4) 回查不到初始止损时, 不再拿"已被推到保本/追踪的止损"当分母        |
//| 逻辑内核: V15.0 状态机 | 自适应布局 | 全功能开关 | 动态风控            |
//+------------------------------------------------------------------+
//--- 注意: link 属性不会单独显示, 它挂在「版权」文字上 —— 用户点击版权行即打开该网址
//--- 编译前请把 MetaEditor 的 CPU 架构设为 X64 Regular, 否则 Apple 芯片 Mac 会报 failed [568]
#property copyright "SunspotAlgo"
#property link      "https://sunspotalgo.com/"
#property version   "4.33"
#property strict
#property description "SunspotAlgo MT5 自动仓位管理系统 (开源跨平台版 Windows / macOS)"
#property description "官网: https://sunspotalgo.com/"
#property description "Telegram 免费4H信号频道: https://t.me/SunspotSignal"
#property description "TradingView 指标页: https://www.tradingview.com/script/u7G1zSjA/"

#include <Trade\Trade.mqh>
#include <Arrays\ArrayLong.mqh> 

CTrade trade;
CArrayLong processedScouts;     

//--- 跨平台字体方案
enum ENUM_UI_FONTSET {
    FONTSET_WINDOWS = 0,   // Windows (微软雅黑)
    FONTSET_MACOS   = 1,   // macOS / Wine (Arial Unicode MS)
    FONTSET_CUSTOM  = 2    // 自定义
};

// ======================= 1. 参数设置 (Inputs) =======================
input group "=== A. 风控设置 (以损定仓模块) ==="
input bool    Enable_Risk_Entry = false;     // [总开关] 启用以损定仓功能
input double  Inp_Risk_Money    = 10.0;    // [参数] 单笔风险金额 (USD)
input bool    Inp_Close_Scout   = false;     // [开关] 补单后平掉试探单
input int     Inp_Scout_Timeout = 60;       // [参数] 侦察单有效时间(秒)

input group "=== B. 核心风控 (管理模块) ==="
input bool    Enable_Auto_BE    = false;     // [开关] 启用自动保本
input double  Inp_BE_Trigger    = 0.7;      // [参数] 保本触发 R值
input bool    Enable_Hard_Trail = true;     // [开关] 启用追踪止盈
input double  Inp_Trail_Start   = 1.5;      // [参数] 追踪启动 R值
input double  Inp_Trail_Back    = 1.0;      // [参数] 追踪回撤 R值
input double  Inp_Hard_TP_R     = 8.0;      // [硬] 硬止盈 R值

input group "=== C. 分批止盈 (可选) ==="
input bool    Enable_Split_TP   = true;     // [开关] 启用分批止盈
input double  Split_TP1_R       = 2.2;     
input double  Split_TP1_Pct     = 0.5;      // 0.5 = 50%
input double  Split_TP2_R       = 4.0;     
input double  Split_TP2_Pct     = 0.5;      // 剩余仓位的比例

input group "=== D. 挂单管理 (Pending) ==="
input int     InpPendingTimeout = 0;      // 挂单超时撤单(分钟, 0为不撤)

input group "=== E. 基础设置 ==="
input ulong   InpEAMagic        = 999777;   
input double  InpSlippage       = 5;        
input double  BE_Offset_R       = 0.1;      // 保本时的微利偏移量

input group "=== F. UI 界面设置 ==="
input int     UI_X_Offset       = 30;           
input int     UI_Y_Offset       = 40;           
input color   ColorBg           = C'20,25,30';  
input color   ColorHeaderBG     = C'35,40,45';  
input color   ColorProfit       = clrDeepSkyBlue;
input color   ColorText         = clrWhiteSmoke;
input color   ColorActive       = clrLimeGreen; 
input color   ColorWarn         = clrOrangeRed; 

input group "=== G. 跨平台适配 (Mac 用户只需改这一组) ==="
input ENUM_UI_FONTSET Inp_FontSet     = FONTSET_WINDOWS; // 界面字体方案 [Mac 请选 macOS]
input string  Inp_Font_CN_Custom      = "";              // 自定义中文字体 (仅选"自定义"时生效)
input string  Inp_Font_EN_Custom      = "";              // 自定义数字字体 (留空则用中文字体)
input double  Inp_UIScale             = 1.0;             // 界面缩放 [1.0=原始; Mac 小屏建议 0.8]
input bool    Inp_EnableSound         = true;            // 提示音效 [Wine 下音频异常时可关闭]

// ======================= 2. 数据结构与全局变量 =======================

enum ENUM_ITEM_TYPE { ITEM_POSITION, ITEM_ORDER };

struct TradeState {
    ENUM_ITEM_TYPE type; 
    ulong  ticket; 
    string symbol; 
    string dirText; 
    long   posType; 
    
    // --- V15 核心数据 ---
    double entryPrice; 
    double originalSLPrice; 
    double initialSLPoints; 
    double maxRatioAchieved; 
    double currentLots; 
    
    // --- V15 状态标记 ---
    bool   be_Done;         
    bool   trail_Active;    
    double lockedR;          // 当前止损锁定的 R 值 (正=已锁利, 负=仍在风险区)
    
    // --- V4.33 坏样本防线 ---
    int    hardTpHits;       // 硬止盈的连续确认计数 (防单次坏样本平仓)
    bool   slMovedPastEntry; // 回查失败且止损已被移到保本/追踪位 → 初始风险不可知
    datetime lastWarnTime;   // 坏样本日志节流时间
    
    // --- 额外功能 ---
    bool   tp1_Done;        
    bool   tp2_Done;        
    double currentR; 
    datetime setupTime; 
    
    // UI 显示
    string statusInfo;       
    string splitInfo;        
    string trailInfo;        
    color  statusColor;
};

TradeState tradeList[]; 

const string UI_PREFIX = "Sunspot_MAX_V42_"; 
const int    PANEL_WIDTH = 1320; 
const int    ROW_HEIGHT = 42;    
const int    HEADER_HEIGHT = 80; // [调整] 增加表头高度以容纳三行信息
const int    SUB_HEADER_HEIGHT = 35;   

const int COL_1 = 50;    // 品种
const int COL_2 = 200;   // R效能
const int COL_3 = 370;   // 智能状态
const int COL_4 = 550;   // 分批止盈
const int COL_5 = 740;   // 追踪止盈
const int COL_6 = 950;   // 入场|初损
const int COL_7 = 1200;  // 手数

//--- V4.33 报价/R 值合理性防线
const double MAX_SANE_R      = 50.0;  // 单次采样允许的最大 R (硬止盈 8R 之上留足余量, 超过即判为坏报价)
const int    HARD_TP_CONFIRM = 2;     // 硬止盈需连续几次有效采样确认
const int    WARN_COOLDOWN_S = 60;    // 同一票据的"坏样本"日志最快间隔(秒), 防止刷屏

string FONT_CN = "Microsoft YaHei";  // 运行期由 Inp_FontSet 决定 (勿直接修改)
string FONT_EN = "Consolas";         // 运行期由 Inp_FontSet 决定 (勿直接修改)
double g_UIScale = 1.0;              // 界面缩放, 1.0 = 原始尺寸

// ======================= 3. 基础辅助函数 =======================

//--- 界面坐标缩放 (只在 CreateLabel / CreateRect 两处生效, 默认 1.0 行为与旧版完全一致)
int US(int v) { return (int)MathRound(v * g_UIScale); }

//--- 字体方案解析: Windows / macOS / 自定义
void ResolveUIStyle() {
    if(Inp_FontSet == FONTSET_MACOS) {
        // macOS 自带 Arial Unicode MS (含完整中日韩字形), Wine 封装环境下最稳
        FONT_CN = "Arial Unicode MS";
        FONT_EN = "Arial Unicode MS";
    } else if(Inp_FontSet == FONTSET_CUSTOM) {
        FONT_CN = (StringLen(Inp_Font_CN_Custom) > 0) ? Inp_Font_CN_Custom : "Microsoft YaHei";
        FONT_EN = (StringLen(Inp_Font_EN_Custom) > 0) ? Inp_Font_EN_Custom : FONT_CN;
    } else {
        FONT_CN = "Microsoft YaHei";
        FONT_EN = "Consolas";
    }
    g_UIScale = (Inp_UIScale > 0.0) ? Inp_UIScale : 1.0;
}

bool IsScoutProcessed(ulong ticket) {
    for(int i=0; i<processedScouts.Total(); i++) if(processedScouts.At(i) == (long)ticket) return true;
    return false;
}

void AddScoutProcessed(ulong ticket) {
    if(!IsScoutProcessed(ticket)) processedScouts.Add((long)ticket);
}

int FindInArray(TradeState &arr[], ulong t) {
    for(int i=0; i<ArraySize(arr); i++) if(arr[i].ticket == t) return i;
    return -1;
}

double GetStrictOriginalSLFromHistory(ulong posTicket) {
    if(!PositionSelectByTicket(posTicket)) return -1.0;
    long posID = PositionGetInteger(POSITION_IDENTIFIER);
    if(HistorySelectByPosition(posID)) {
        int total = HistoryOrdersTotal();
        for(int i=total-1; i>=0; i--) {
            ulong ordTicket = HistoryOrderGetTicket(i);
            if(ordTicket > 0) {
                double sl = HistoryOrderGetDouble(ordTicket, ORDER_SL);
                if(sl > 0.00001) return sl;
            }
        }
    }
    return -1.0; 
}

void DeleteRow(int r) {
    string i = (string)r;
    ObjectDelete(0, UI_PREFIX+"D_"+i+"_1"); ObjectDelete(0, UI_PREFIX+"D_"+i+"_2");
    ObjectDelete(0, UI_PREFIX+"D_"+i+"_3"); ObjectDelete(0, UI_PREFIX+"D_"+i+"_4");
    ObjectDelete(0, UI_PREFIX+"D_"+i+"_5"); ObjectDelete(0, UI_PREFIX+"D_"+i+"_6");
    ObjectDelete(0, UI_PREFIX+"D_"+i+"_7"); 
    ObjectDelete(0, UI_PREFIX+"L_"+i);
}

void CreateLabel(string name, int x, int y, string text, string font, int size, color clr, bool bold=false, int anchor=ANCHOR_LEFT_UPPER) {
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, US(x));
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, US(y));
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetString(0, name, OBJPROP_FONT, font);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
}

void CreateRect(string name, int x, int y, int w, int h, color bg) {
    if(ObjectFind(0, name) < 0) {
        ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
    }
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, US(x));
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, US(y));
    ObjectSetInteger(0, name, OBJPROP_XSIZE, US(w));
    ObjectSetInteger(0, name, OBJPROP_YSIZE, US(h));
    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

// ======================= 4. 策略逻辑 (侦察 + 管理) =======================

void CheckAndExecuteEntry(ulong ticket, string symbol, ENUM_ORDER_TYPE type, double entry, double sl, double vol, long magic, long time, bool isMarket) {
    if(IsScoutProcessed(ticket)) return;           
    if(magic == InpEAMagic) return;                
    if(sl <= 0) return;                            
    if(TimeCurrent() > time && (TimeCurrent() - time > Inp_Scout_Timeout)) return; 
    
    if(!SymbolSelect(symbol, true)) return; 
    double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    if(minVol <= 0) return; 

    if(MathAbs(vol - minVol) > 0.0001) return;

    double lossPerLot = 0.0;
    if(!OrderCalcProfit(type, symbol, 1.0, entry, sl, lossPerLot)) return;
    lossPerLot = MathAbs(lossPerLot);
    if(lossPerLot <= 0.001) return;

    double targetLots = Inp_Risk_Money / lossPerLot;
    double lotsToOpen = Inp_Close_Scout ? targetLots : (targetLots - minVol);

    double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    double max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    
    if(step <= 0) return;
    lotsToOpen = MathFloor(lotsToOpen / step) * step;
    
    if(lotsToOpen < minVol) { 
        AddScoutProcessed(ticket); 
        return; 
    }
    if(lotsToOpen > max) lotsToOpen = max;

    bool res = false;
    string comm = "Sunspot Risk $" + DoubleToString(Inp_Risk_Money, 0); 
    
    if(isMarket) {
        res = (type == ORDER_TYPE_BUY) ? trade.Buy(lotsToOpen, symbol, 0, sl, 0, comm) : trade.Sell(lotsToOpen, symbol, 0, sl, 0, comm);
    } else {
        ENUM_ORDER_TYPE pt = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        res = trade.OrderOpen(symbol, pt, lotsToOpen, 0, entry, sl, 0, ORDER_TIME_GTC, 0, comm);
    }

    if(res && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED)) {
        AddScoutProcessed(ticket); 
        if(Inp_EnableSound) PlaySound("Ok.wav");
        if(Inp_Close_Scout) {
            if(isMarket) trade.PositionClose(ticket);
            else trade.OrderDelete(ticket);
        }
    }
}

void ProcessRiskEntryLogic() {
    if(!Enable_Risk_Entry) return;

    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        CheckAndExecuteEntry(ticket, PositionGetString(POSITION_SYMBOL), 
                             (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE), 
                             PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL), 
                             PositionGetDouble(POSITION_VOLUME), PositionGetInteger(POSITION_MAGIC),
                             PositionGetInteger(POSITION_TIME), true);
    }
    for(int i = OrdersTotal() - 1; i >= 0; i--) {
        ulong ticket = OrderGetTicket(i);
        if(ticket <= 0) continue;
        ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
        ENUM_ORDER_TYPE calcType = (type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_BUY_STOP) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        CheckAndExecuteEntry(ticket, OrderGetString(ORDER_SYMBOL), calcType,
                             OrderGetDouble(ORDER_PRICE_OPEN), OrderGetDouble(ORDER_SL), 
                             OrderGetDouble(ORDER_VOLUME_INITIAL), OrderGetInteger(ORDER_MAGIC),
                             OrderGetInteger(ORDER_TIME_SETUP), false);
    }
}

void ProcessPendingOrderStrategy(int i) {
    if(InpPendingTimeout > 0) {
        long elapsed = TimeCurrent() - tradeList[i].setupTime;
        long limitSec = InpPendingTimeout * 60;
        long remain = limitSec - elapsed;
        
        if(remain <= 0) {
            trade.OrderDelete(tradeList[i].ticket);
            tradeList[i].statusInfo = "超时已撤单"; 
            tradeList[i].statusColor = ColorWarn;
        } else {
            tradeList[i].statusInfo = "倒计时: " + (string)(remain/60) + "分";
            tradeList[i].statusColor = clrWheat;
        }
    } else {
        tradeList[i].statusInfo = "挂单监控中"; 
        tradeList[i].statusColor = clrSilver;
    }
    tradeList[i].splitInfo = "- -";
    tradeList[i].trailInfo = "等待成交";
}

void ProcessSplitTP(int i) {
    if (tradeList[i].currentLots <= 0) return;

    if(!tradeList[i].tp1_Done && tradeList[i].currentR >= Split_TP1_R) {
        double vol = tradeList[i].currentLots;
        double step = SymbolInfoDouble(tradeList[i].symbol, SYMBOL_VOLUME_STEP);
        double amt = MathFloor((vol * Split_TP1_Pct)/step)*step;
        
        if(amt >= step) {
            if(trade.PositionClosePartial(tradeList[i].ticket, amt)) {
                tradeList[i].tp1_Done = true;
                Print("TP1 Executed for Ticket: ", tradeList[i].ticket);
            }
        } else { tradeList[i].tp1_Done = true; }
    }
    
    if(!tradeList[i].tp2_Done && tradeList[i].currentR >= Split_TP2_R) {
        double vol = tradeList[i].currentLots;
        double step = SymbolInfoDouble(tradeList[i].symbol, SYMBOL_VOLUME_STEP);
        double amt = MathFloor((vol * Split_TP2_Pct)/step)*step;
        
        if(amt >= step) {
            if(trade.PositionClosePartial(tradeList[i].ticket, amt)) {
                tradeList[i].tp2_Done = true;
                Print("TP2 Executed for Ticket: ", tradeList[i].ticket);
            }
        } else { tradeList[i].tp2_Done = true; }
    }
}

//--- 当前止损相对"初始风险"锁定的 R 值 (正数 = 已锁利, 负数 = 仍处风险区)
double CalcLockedR(int i, double slPrice, long type, double entry, double point) {
    if(slPrice <= 0.0 || point <= 0.0) return 0.0;
    if(tradeList[i].initialSLPoints <= 0.00001) return 0.0;
    double d = (type == POSITION_TYPE_BUY) ? (slPrice - entry) : (entry - slPrice);
    return d / point / tradeList[i].initialSLPoints;
}

//--- 「追踪止盈」列文案
//    严格按"实际开启的模块 + 当前进度"推导下一步, 不再用错误的开关判断:
//      追踪已激活            -> 追踪中 锁X.XXR
//      保本开着且还没做完      -> 等待保本 > x.xxR   (保本是追踪的前置门槛)
//      其余且追踪开着          -> 等待追踪 > x.xxR   (含: 保本关闭 / 保本已完成)
//      追踪关闭              -> [追踪已关闭]
string BuildTrailInfo(int i) {
    if(Enable_Hard_Trail) {
        if(tradeList[i].trail_Active)
            return "追踪中 锁" + DoubleToString(tradeList[i].lockedR, 2) + "R";
        if(Enable_Auto_BE && !tradeList[i].be_Done)
            return "等待保本 > " + DoubleToString(Inp_BE_Trigger, 2) + "R";
        return "等待追踪 > " + DoubleToString(Inp_Trail_Start, 2) + "R";
    }
    return "[追踪已关闭]";
}

//--- 报价有效性: 品种不在 Market Watch / 终端刚启动未同步时, BID/ASK 会返回 0。
//    拿 0 当现价去算空单浮盈, 会得到 "入场价/点" 这种天文数字, R 直接爆表。
bool EnsureSymbolReady(const string symbol) {
    // 把品种加进 Market Watch, 这样终端才会持续推送该品种的报价
    return SymbolSelect(symbol, true);
}

bool IsQuoteValid(const string symbol, double &bid, double &ask) {
    bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    if(bid <= 0.0 || ask <= 0.0) return false;
    if(ask < bid) return false;
    return true;
}

//--- 丢弃坏样本: 保留上一次有效值继续显示(不污染面板), 日志按票据节流
void MarkBadSample(int i, const string reason) {
    tradeList[i].statusInfo  = "报价异常 | 跳过";
    tradeList[i].statusColor = ColorWarn;
    if(TimeCurrent() - tradeList[i].lastWarnTime >= WARN_COOLDOWN_S) {
        tradeList[i].lastWarnTime = TimeCurrent();
        Print("Sunspot: 丢弃异常报价样本 #", tradeList[i].ticket, " ", tradeList[i].symbol, " | ", reason);
    }
}

void ProcessHardLogic(int i, double point, MqlTick &tick) {
    long type = tradeList[i].posType;
    double entry = tradeList[i].entryPrice;
    int digits = (int)SymbolInfoInteger(tradeList[i].symbol, SYMBOL_DIGITS);
    
    double curPrice = (type == POSITION_TYPE_BUY) ? tick.bid : tick.ask;
    double profitPoints = (type == POSITION_TYPE_BUY) ? (curPrice - entry) / point : (entry - curPrice) / point;
    
    double currentR = 0.0;
    if(tradeList[i].initialSLPoints > 0.00001) {
        currentR = profitPoints / tradeList[i].initialSLPoints;
    }
    
    //--- 坏样本防线: 超出合理范围的 R 一律丢弃, 不更新"最高值",
    //    也不触发保本/追踪/硬止盈 (0 报价造成的天文数字就死在这里)
    if(MathAbs(currentR) > MAX_SANE_R) {
        MarkBadSample(i, "R=" + DoubleToString(currentR, 2) + " 超出上限");
        return;
    }
    
    tradeList[i].currentR = currentR;
    if(currentR > tradeList[i].maxRatioAchieved) tradeList[i].maxRatioAchieved = currentR;
    
    //--- 自愈: 内存里若残留旧版算出的脏"最高值"(天文数字), 就地作废重建。
    //    否则它会一直被当成追踪基准 → 目标止损价离谱 → 每次改单都被拒 → 该单实际裸奔。
    if(tradeList[i].maxRatioAchieved > MAX_SANE_R) {
        tradeList[i].maxRatioAchieved = MathMax(currentR, 0.0);
        tradeList[i].trail_Active = false;
        tradeList[i].hardTpHits   = 0;
        if(TimeCurrent() - tradeList[i].lastWarnTime >= WARN_COOLDOWN_S) {
            tradeList[i].lastWarnTime = TimeCurrent();
            Print("Sunspot: 清理异常「最高R」#", tradeList[i].ticket, " ", tradeList[i].symbol, " (旧版脏数据)");
        }
    }
    
    if(!Enable_Auto_BE && !Enable_Hard_Trail && !Enable_Split_TP) {
        tradeList[i].statusInfo = "纯监控模式";
        tradeList[i].statusColor = clrSilver;
    } else {
        tradeList[i].statusInfo = "风控监控中";
        tradeList[i].statusColor = clrSilver;
    }
    
    //--- 「追踪止盈」列文案统一由函数末尾的 BuildTrailInfo() 生成 (取决于实际开启的模块)
    
    if(Enable_Split_TP) {
        if(!tradeList[i].tp1_Done) tradeList[i].splitInfo = "待分批1 > " + DoubleToString(Split_TP1_R, 2) + "R";
        else if(!tradeList[i].tp2_Done) tradeList[i].splitInfo = "待分批2 > " + DoubleToString(Split_TP2_R, 2) + "R";
        else tradeList[i].splitInfo = "分批完成";
    } else {
        tradeList[i].splitInfo = "[功能已关闭]";
    }

    // Auto BE
    if (Enable_Auto_BE && !tradeList[i].be_Done && currentR >= Inp_BE_Trigger) {
        double beDist = BE_Offset_R * tradeList[i].initialSLPoints * point;
        double newSL = (type == POSITION_TYPE_BUY) ? entry + beDist : entry - beDist;
        newSL = NormalizeDouble(newSL, digits);
        double currentSL = PositionGetDouble(POSITION_SL);
        bool isBetter = (type == POSITION_TYPE_BUY) ? (newSL > currentSL) : (currentSL == 0 || newSL < currentSL);
        
        if (isBetter) {
            if (trade.PositionModify(tradeList[i].ticket, newSL, PositionGetDouble(POSITION_TP))) tradeList[i].be_Done = true; 
        } else {
            tradeList[i].be_Done = true; 
        }
    }

    // Trailing
    if (Enable_Hard_Trail && tradeList[i].maxRatioAchieved >= Inp_Trail_Start) {
        if (!tradeList[i].trail_Active) {
            tradeList[i].trail_Active = true;
            tradeList[i].be_Done = true; 
        }
        double targetR = tradeList[i].maxRatioAchieved - Inp_Trail_Back;
        if(targetR < BE_Offset_R) targetR = BE_Offset_R;
        double slDist = targetR * tradeList[i].initialSLPoints * point;
        double newSL = (type == POSITION_TYPE_BUY) ? entry + slDist : entry - slDist;
        newSL = NormalizeDouble(newSL, digits);
        double currentSL = PositionGetDouble(POSITION_SL);
        bool shouldModify = false;
        
        if (type == POSITION_TYPE_BUY) { if (newSL > currentSL + point) shouldModify = true; } 
        else { if (currentSL == 0 || newSL < currentSL - point) shouldModify = true; }
        
        if (shouldModify) trade.PositionModify(tradeList[i].ticket, newSL, PositionGetDouble(POSITION_TP));
    }
    
    // Hard TP (需连续确认: 单次坏样本不允许直接平掉整仓)
    if (currentR >= Inp_Hard_TP_R) {
        tradeList[i].hardTpHits++;
        if(tradeList[i].hardTpHits >= HARD_TP_CONFIRM) {
            if(trade.PositionClose(tradeList[i].ticket)) tradeList[i].statusInfo = "止盈已平仓";
        }
    } else {
        tradeList[i].hardTpHits = 0;
    }
    
    // Split TP
    if(Enable_Split_TP) {
        ProcessSplitTP(i);
        if(!tradeList[i].tp1_Done) tradeList[i].splitInfo = "待分批1 > " + DoubleToString(Split_TP1_R, 2) + "R";
        else if(!tradeList[i].tp2_Done) tradeList[i].splitInfo = "待分批2 > " + DoubleToString(Split_TP2_R, 2) + "R";
        else tradeList[i].splitInfo = "分批完成";
    }
    
    //---- 面板文案: 严格反映"实际开启的模块 + 当前进度", 避免误导 ----
    //     先读一次真实止损, 供两列共用
    tradeList[i].lockedR = CalcLockedR(i, PositionGetDouble(POSITION_SL), type, entry, point);
    
    if(tradeList[i].trail_Active) {
        // 追踪已接管: 只显示追踪态 (be_Done 可能只是为了抑制保本逻辑而置位, 不代表真的保本了)
        tradeList[i].statusInfo  = "硬追踪激活";
        tradeList[i].statusColor = ColorActive;
    } else if(Enable_Auto_BE && tradeList[i].be_Done) {
        // 只有保本模块"确实开着"且已完成, 才显示已保本
        tradeList[i].statusInfo  = "已保本 锁" + DoubleToString(tradeList[i].lockedR, 2) + "R";
        tradeList[i].statusColor = clrGold;
    }
    
    tradeList[i].trailInfo = BuildTrailInfo(i);
}

// ======================= 5. 数据刷新 =======================

void RefreshTradeList() {
    TradeState finalArray[];
    
    for(int i=0; i<ArraySize(tradeList); i++) {
        bool stillExists = false;
        if(tradeList[i].type == ITEM_POSITION) {
            if(PositionSelectByTicket(tradeList[i].ticket)) stillExists = true;
        } else {
            if(OrderSelect(tradeList[i].ticket)) stillExists = true;
        }
        if(stillExists) {
            int n = ArraySize(finalArray);
            ArrayResize(finalArray, n+1);
            finalArray[n] = tradeList[i];
        }
    }
    
    for(int i=0; i<PositionsTotal(); i++) {
        ulong t = PositionGetTicket(i);
        if(!PositionSelectByTicket(t)) continue;
        
        if(FindInArray(finalArray, t) == -1) {
            TradeState newItem; ZeroMemory(newItem);
            newItem.type = ITEM_POSITION;
            newItem.ticket = t;
            newItem.symbol = PositionGetString(POSITION_SYMBOL);
            EnsureSymbolReady(newItem.symbol);   // 先订阅行情, 否则下面读到的 BID/ASK 可能是 0
            newItem.entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            newItem.currentLots = PositionGetDouble(POSITION_VOLUME);
            newItem.posType = PositionGetInteger(POSITION_TYPE);
            newItem.dirText = (newItem.posType == POSITION_TYPE_BUY) ? "[多]" : "[空]";
            
            double origSL = GetStrictOriginalSLFromHistory(t);
            if(origSL <= 0) {
                // 回查失败时的兜底: 只有"止损仍在亏损侧"才敢当作初始风险。
                // 止损若已被 EA 或手动推到保本/追踪位, 它就不是初始止损,
                // 拿它当分母会把 R 放大几十上百倍 —— 面板上那个 346.70 就是这么来的
                double currentLiveSL = PositionGetDouble(POSITION_SL);
                bool stillLosingSide = (newItem.posType == POSITION_TYPE_BUY)
                                       ? (currentLiveSL > 0.0 && currentLiveSL < newItem.entryPrice)
                                       : (currentLiveSL > newItem.entryPrice);
                if(stillLosingSide) origSL = currentLiveSL;
                else if(currentLiveSL > 0.0) newItem.slMovedPastEntry = true;
            }

            newItem.originalSLPrice = origSL; 

            if(origSL > 0) {
                double point = SymbolInfoDouble(newItem.symbol, SYMBOL_POINT);
                newItem.initialSLPoints = (point > 0.0) ? MathAbs(newItem.entryPrice - origSL) / point : 0.0;
                
                double cSL = PositionGetDouble(POSITION_SL);
                if(newItem.posType==POSITION_TYPE_BUY && cSL>=newItem.entryPrice) newItem.be_Done=true;
                if(newItem.posType==POSITION_TYPE_SELL && cSL>0 && cSL<=newItem.entryPrice) newItem.be_Done=true;
                
                double currentR = 0;
                if(newItem.initialSLPoints > 0) {
                    double qBid = 0.0, qAsk = 0.0;
                    if(IsQuoteValid(newItem.symbol, qBid, qAsk)) {
                        double curP = (newItem.posType==POSITION_TYPE_BUY) ? qBid : qAsk;
                        double profP = (newItem.posType==POSITION_TYPE_BUY) ? (curP-newItem.entryPrice) : (newItem.entryPrice-curP);
                        currentR = (profP/point) / newItem.initialSLPoints;
                    } else {
                        Print("Sunspot: ", newItem.symbol, " 报价无效(bid/ask=0), 本次不做 R 初始化");
                    }
                }
                // 只接受合理范围内的样本, 否则宁可不设"最高值"
                if(currentR > Inp_Trail_Start && currentR <= MAX_SANE_R) {
                    newItem.maxRatioAchieved = currentR;
                    if(Enable_Hard_Trail) { newItem.trail_Active = true; newItem.be_Done = true; }
                }
            } else {
                newItem.initialSLPoints = 0;
            }
            int n = ArraySize(finalArray); ArrayResize(finalArray, n+1); finalArray[n] = newItem;
        }
    }
    
    for(int i=0; i<OrdersTotal(); i++) {
        ulong t = OrderGetTicket(i);
        if(!OrderSelect(t)) continue;
        
        if(FindInArray(finalArray, t) == -1) {
            TradeState newItem; ZeroMemory(newItem);
            newItem.type = ITEM_ORDER;
            newItem.ticket = t;
            newItem.symbol = OrderGetString(ORDER_SYMBOL);
            newItem.entryPrice = OrderGetDouble(ORDER_PRICE_OPEN);
            newItem.originalSLPrice = OrderGetDouble(ORDER_SL);
            newItem.setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
            long oType = OrderGetInteger(ORDER_TYPE);
            if(oType == ORDER_TYPE_BUY_LIMIT || oType == ORDER_TYPE_BUY_STOP || oType == ORDER_TYPE_BUY_STOP_LIMIT) {
                newItem.dirText = "[挂多]"; newItem.posType = POSITION_TYPE_BUY;
            } else {
                newItem.dirText = "[挂空]"; newItem.posType = POSITION_TYPE_SELL;
            }
            int n = ArraySize(finalArray); ArrayResize(finalArray, n+1); finalArray[n] = newItem;
        }
    }
    
    ArrayResize(tradeList, ArraySize(finalArray));
    for(int i=0; i<ArraySize(finalArray); i++) tradeList[i] = finalArray[i];
}

void RunStrategyLogic() {
    ProcessRiskEntryLogic();

    for(int i=0; i<ArraySize(tradeList); i++) {
        if(tradeList[i].type == ITEM_ORDER) {
            ProcessPendingOrderStrategy(i);
            continue;
        }
        
        if(PositionSelectByTicket(tradeList[i].ticket)) {
            tradeList[i].currentLots = PositionGetDouble(POSITION_VOLUME);
        } else { continue; }

        if(tradeList[i].initialSLPoints <= 0.1) {
            tradeList[i].statusInfo = tradeList[i].slMovedPastEntry ? "基准缺失 | 忽略" : "无初损 | 忽略"; 
            tradeList[i].splitInfo = "不可用";
            tradeList[i].trailInfo = "不可用";
            tradeList[i].statusColor = ColorWarn;
            tradeList[i].currentR = 0;
            continue;
        }

        string symbol = tradeList[i].symbol;
        EnsureSymbolReady(symbol);   // 品种未订阅时, 下面读到的 tick / point 都不可信
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0.0) { MarkBadSample(i, "取不到 point"); continue; }
        MqlTick tick; 
        if(!SymbolInfoTick(symbol, tick)) continue;
        if(tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid) {
            MarkBadSample(i, "tick异常 bid=" + DoubleToString(tick.bid, 5) + " ask=" + DoubleToString(tick.ask, 5));
            continue;
        }
        
        ProcessHardLogic(i, point, tick);
    }
}

// ======================= 6. UI 渲染 (Dashboard) =======================
void DrawDashboard() {
    int x = UI_X_Offset;
    int y = UI_Y_Offset;
    int rows = ArraySize(tradeList); 
    if(rows == 0) rows = 1; 
    
    int totalH = HEADER_HEIGHT + SUB_HEADER_HEIGHT + (rows * ROW_HEIGHT) + 10;
    
    CreateRect(UI_PREFIX+"BG", x, y, PANEL_WIDTH, totalH, ColorBg);
    CreateRect(UI_PREFIX+"BG_Head", x, y, PANEL_WIDTH, HEADER_HEIGHT, ColorHeaderBG);
    CreateRect(UI_PREFIX+"BG_Acc", x, y, 5, totalH, clrGold); 

    CreateLabel(UI_PREFIX+"Title", x+20, y+10, "SunspotAlgo 自动仓位管理系统", FONT_CN, 13, clrGold, true);
    CreateLabel(UI_PREFIX+"Sub", x+20, y+45, "sunspotalgo.com | TG: @SunspotSignal | TV: SunspotAlgo", FONT_CN, 8, clrSilver);

    // 第一行: 保本/追踪
    string statusBE = Enable_Auto_BE ? "[开启]" : "[关闭]";
    string statusTrail = Enable_Hard_Trail ? "[开启]" : "[关闭]";
    string strL1 = "风控: 保本" + statusBE + " " + DoubleToString(Inp_BE_Trigger,2) + "R | " +
                   "追踪" + statusTrail + " " + DoubleToString(Inp_Trail_Start,2) + "R / -" + DoubleToString(Inp_Trail_Back,2) + "R";
    
    // 第二行: 分批/挂单
    string strL2 = "";
    if(Enable_Split_TP) {
        strL2 += "分批: 第一笔(" + DoubleToString(Split_TP1_R, 2) + "R/" + DoubleToString(Split_TP1_Pct*100, 0) + "%) ";
        strL2 += "第二笔(" + DoubleToString(Split_TP2_R, 2) + "R/" + DoubleToString(Split_TP2_Pct*100, 0) + "%)";
    } else {
        strL2 += "分批: [关闭]";
    }
    strL2 += " | 挂单: ";
    if(InpPendingTimeout > 0) strL2 += IntegerToString(InpPendingTimeout) + "分撤";
    else strL2 += "常驻";

    // 第三行: 以损定仓
    string riskStatus = Enable_Risk_Entry ? "[开启]" : "[关闭]";
    string riskStr = "以损定仓" + riskStatus + " | 单笔风险: $" + DoubleToString(Inp_Risk_Money, 0);
    if(Enable_Risk_Entry) {
        riskStr += Inp_Close_Scout ? " (平试探)" : " (留试探)";
    }

    CreateLabel(UI_PREFIX+"P_L1", x+PANEL_WIDTH-20, y+10, strL1, FONT_CN, 8, clrWhiteSmoke, false, ANCHOR_RIGHT_UPPER);
    CreateLabel(UI_PREFIX+"P_L2", x+PANEL_WIDTH-20, y+28, strL2, FONT_CN, 8, clrSilver, false, ANCHOR_RIGHT_UPPER);
    CreateLabel(UI_PREFIX+"P_L3", x+PANEL_WIDTH-20, y+46, riskStr, FONT_CN, 8, clrWheat, false, ANCHOR_RIGHT_UPPER); // [新增第三行]
    
    int y_h = y + HEADER_HEIGHT + 8;
    CreateLabel(UI_PREFIX+"H1", x+COL_1, y_h, "交易品种", FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);
    CreateLabel(UI_PREFIX+"H2", x+COL_2, y_h, "R效能 (盈亏比)", FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);
    CreateLabel(UI_PREFIX+"H3", x+COL_3, y_h, "智能状态", FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);
    CreateLabel(UI_PREFIX+"H4", x+COL_4, y_h, "分批止盈", FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);
    CreateLabel(UI_PREFIX+"H5", x+COL_5, y_h, "追踪止盈", FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);
    CreateLabel(UI_PREFIX+"H6", x+COL_6, y_h, "入场 | 初损", FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);
    CreateLabel(UI_PREFIX+"H7", x+COL_7, y_h, "持仓手数", FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);

    int y_d = y_h + SUB_HEADER_HEIGHT;
    
    if(ArraySize(tradeList) == 0) {
        CreateLabel(UI_PREFIX+"D_Empty", x+(PANEL_WIDTH/2), y_d+10, "系统待机中... (等待开仓/挂单)", FONT_CN, 11, clrSilver, false, ANCHOR_UPPER);
    } else {
        if(ObjectFind(0, UI_PREFIX+"D_Empty") >= 0) ObjectDelete(0, UI_PREFIX+"D_Empty");

        for(int i=0; i<ArraySize(tradeList); i++) {
            int curY = y_d + (i * ROW_HEIGHT);
            int textY = curY + 12; 
            
            string c1 = tradeList[i].symbol + " " + tradeList[i].dirText; 
            string c2, c3, c4, c5, c6, c7;
            color  c3Color = clrSilver;
            
            int digits = (int)SymbolInfoInteger(tradeList[i].symbol, SYMBOL_DIGITS);
            string strEntry = DoubleToString(tradeList[i].entryPrice, digits);
            string strSL = (tradeList[i].originalSLPrice > 0.00001) ? DoubleToString(tradeList[i].originalSLPrice, digits) : "无";
            c6 = strEntry + " | " + strSL;
            
            if(tradeList[i].type == ITEM_ORDER) {
                c2 = "- -"; 
                c3Color = clrWheat; 
            } 
            else {
                if(tradeList[i].initialSLPoints > 0) {
                    string maxStr = (tradeList[i].maxRatioAchieved > 0) ? "(最高:" + DoubleToString(tradeList[i].maxRatioAchieved, 2) + ")" : "";
                    c2 = DoubleToString(tradeList[i].currentR, 2) + " R " + maxStr; 
                    if(tradeList[i].currentR > 0) c3Color = ColorProfit;
                    else c3Color = clrSilver;
                } else {
                    c2 = "无初损"; 
                    c3Color = clrDimGray;
                }
            }
            
            c3 = tradeList[i].statusInfo;
            c4 = tradeList[i].splitInfo;
            c5 = tradeList[i].trailInfo;
            c7 = DoubleToString(tradeList[i].currentLots, 2);

            CreateLabel(UI_PREFIX+"D_"+(string)i+"_1", x+COL_1, textY, c1, FONT_CN, 10, clrWhite, true, ANCHOR_UPPER); 
            CreateLabel(UI_PREFIX+"D_"+(string)i+"_2", x+COL_2, textY, c2, FONT_CN, 11, c3Color, false, ANCHOR_UPPER); 
            CreateLabel(UI_PREFIX+"D_"+(string)i+"_3", x+COL_3, textY, c3, FONT_CN, 10, tradeList[i].statusColor, false, ANCHOR_UPPER);
            CreateLabel(UI_PREFIX+"D_"+(string)i+"_4", x+COL_4, textY, c4, FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);
            CreateLabel(UI_PREFIX+"D_"+(string)i+"_5", x+COL_5, textY, c5, FONT_CN, 10, clrSilver, false, ANCHOR_UPPER);
            CreateLabel(UI_PREFIX+"D_"+(string)i+"_6", x+COL_6, textY, c6, FONT_CN, 10, clrWheat, false, ANCHOR_UPPER);
            CreateLabel(UI_PREFIX+"D_"+(string)i+"_7", x+COL_7, textY, c7, FONT_CN, 11, ColorText, false, ANCHOR_UPPER);
            
            CreateRect(UI_PREFIX+"L_"+(string)i, x+15, curY+ROW_HEIGHT, PANEL_WIDTH-30, 1, C'45,50,58'); 
        }
    }
    
    for(int k = ArraySize(tradeList); k < ArraySize(tradeList) + 20; k++) DeleteRow(k);
    
    ChartRedraw();
}

// ======================= 7. 主程序入口 =======================
int OnInit() {
    trade.SetExpertMagicNumber(InpEAMagic);
    trade.SetDeviationInPoints((ulong)InpSlippage);
    trade.SetAsyncMode(false); 
    
    ResolveUIStyle();
    
    ObjectsDeleteAll(0, UI_PREFIX);
    ChartRedraw();
    
    EventSetMillisecondTimer(500);
    Print("[SunspotAlgo] MT5 自动仓位管理系统已加载 | 官网: https://sunspotalgo.com/ | Telegram 免费4H信号频道: https://t.me/SunspotSignal | TradingView: https://www.tradingview.com/script/u7G1zSjA/");
    return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) {
    EventKillTimer();
    processedScouts.Shutdown();
    ObjectsDeleteAll(0, UI_PREFIX);
    ChartRedraw();
}

void OnTick() {
    ProcessRiskEntryLogic();
    if(PositionsTotal() > 0 || OrdersTotal() > 0) {
        RefreshTradeList(); 
        RunStrategyLogic(); 
    }
}

void OnTimer() { 
    RefreshTradeList();    
    RunStrategyLogic();    
    DrawDashboard(); 
}
