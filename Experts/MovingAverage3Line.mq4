//+------------------------------------------------------------------+
//|                                      General circulation EMA.mq4 |
//|                                      Copyright 2023-2023, fxowl. |
//|                                              http://www.mql4.com |
//+------------------------------------------------------------------+

/****************************************************************************************************
 * @file MovingAverage3Line.mq4
 * @author fxowl (https://twitter.com/UraRust)
 * @brief 移動平均線(EMA)で自動売買するEAです。
 * mt4標準のMAのEAをベースにカスタムしています。
 * 短期EMAが中期、長期EMAを上に抜けたら買い、短期EMAが中期、長期EMAを下に抜けたら売ります。
 * 決済はトレンドが終了したタイミングで決済します。
 * ロスカットはSLに設定した値で行います。
 * SLの値が0の場合は、「発注時の価格　+(-)（発注時のATRの値　×　SLAtrRanege）」でロスカットを設定します。
 *
 * 現在検証が十分に行われていなので、本番環境で稼働させる場合は自己責任でお願いします。
 *
 * @version 0.2
 * @date 2023-04-19
 *
 * @copyright Copyright (c) 2023
 *****************************************************************************************************/

#include <EAStrategy/MovingAverage.mqh>
#include <stderror.mqh>
#include <stdlib.mqh>

#property copyright "2023_04, fxowl."
#property description "移動平均線(EMA)で自動売買するEAです。"

#define MAGICMA 20230419
// ユーザー入力値
input double Lots = 0.1;
input double MaximumRisk = 0.02; // 余剰証拠金 * MaximumRisk / 1000 = lot
input double DecreaseFactor = 3; // 連敗時にロット数を減少する係数
input int MovingPeriod1 = 5; // 短期EMA期間
input int MovingShift1 = 0; // 短期EMA表示移動
input int MovingPeriod2 = 20; // 中期EMA期間
input int MovingShift2 = 0; // 中期EMA表示移動
input int MovingPeriod3 = 40; // 長期EMA期間
input int MovingShift3 = 0; // 長期EMA表示移動
input int SL = 0; // ストップロス
input int TP = 0; // テイクプロフィット（TPAtrRanegeが0以上の場合は無効）
input double SLAtrRanege = 2.5; // SLが0の場合は、[発注時ATR×設定値+(-)価格]でロスカット
input double TPAtrRanege = 0.0; // [発注時ATR×設定値+(-)価格]でTPを設定,設定値が0の場合はTPの値を使用する
/**
 * @brief メイン処理
 *
 */
void OnTick()
{
    // 　begin 速度計測
    // static ulong _sum = 0; // 合計
    // static int _count = -10; // カウント
    // ulong _start = GetMicrosecondCount(); // 開始時刻

    // 　バーが100未満、自動売買が許可されていない場合は処理を中断
    if (Bars < 100 || IsTradeAllowed() == false) return;

    if (CalculateCurrentOrders(Symbol()) == 0)
        // ポジションを持っていない場合は発注
        CheckForOpen();
    else
        // ポジションがある場合は決済
        CheckForClose();

    // 　end 速度計測
    // if (_count >= 0) _sum += GetMicrosecondCount() - _start;
    // _count++;
    // if (_count == 100) {
    //     Print("100 ticks = ", _sum, " μs");
    //     ExpertRemove();
    // }
}

/**
 * @brief 保有しているポジション数を返す
 *
 * @param symbol
 * @return int
 */
int CalculateCurrentOrders(string symbol)
{
    int buys = 0, sells = 0;
    // 保有しているポジションをチェック
    for (int i = 0; i < OrdersTotal(); i++) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) break;
        if (OrderSymbol() == Symbol() && OrderMagicNumber() == MAGICMA) {
            if (OrderType() == OP_BUY) buys++;
            if (OrderType() == OP_SELL) sells++;
        }
    }
    //--- return orders volume
    if (buys > 0)
        return (buys);
    else
        return (-sells);
}

/**
 * @brief 取引履歴の損失数を基に、ロット数を最適化する
 * @return double
 */
double LotsOptimized()
{
    double lot = Lots;
    int orders = HistoryTotal();
    int losses = 0; // 損失を出しているポジション数

    // 現在アカウントの余剰証拠金 * MaximumRisk / 1000
    lot = NormalizeDouble(AccountFreeMargin() * MaximumRisk / 1000.0, 1);

    // ロットの減少調整数値が0以上
    if (DecreaseFactor > 0) {
        for (int i = orders - 1; i >= 0; i--) {
            if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) == false) {
                Print("Error in history!");
                break;
            }
            if (OrderSymbol() != Symbol() || OrderType() > OP_SELL) continue;
            // 現在選択中の注文の損益がプラスなら終了
            if (OrderProfit() > 0) break;
            // 現在選択中の注文の損益がマイナスなら加算
            if (OrderProfit() < 0) losses++;
        }
        if (losses > 1) lot = NormalizeDouble(lot - lot * losses / DecreaseFactor, 1);
    }

    if (lot < 0.01) lot = 0.01;

    return (lot);
}

/**
 * @brief 発注処理
 *
 */
void CheckForOpen()
{
    // 新しいバーの最初のティックのみトレードする
    if (Volume[0] > 1) return;

    MovingAverage3Line* ma_prev = createMovingAverage3Line(Symbol(), PERIOD_CURRENT, 1);
    MovingAverage3Line* ma1 = createMovingAverage3Line(Symbol(), PERIOD_CURRENT);
    MovingAverage3Line* ma2 = createMovingAverage3Line(Symbol(), getNextHigherTimeFrame((ENUM_TIMEFRAMES)_Period));
    MovingAverage3Line* ma3 = createMovingAverage3Line(Symbol(), get2NextHigherTimeFrame((ENUM_TIMEFRAMES)_Period));
    // double cci = iCCI(NULL, PERIOD_CURRENT, 14, (PRICE_HIGH + PRICE_LOW + PRICE_CLOSE) / 3, 0);

    int res;
    double sl;
    double tp = 0;

    // TODO:発注送信に失敗した場合のリトライをどうするか？
    /** sell entry ***************************************************************************************************************/
    if (ma_prev.IsStage2() && ma1.IsSellEntry() && ma2.IsDownTrend() && ma3.IsDownTrend()) {
        sl = SL == 0 ? Bid + NormalizeDouble(getAtr() * SLAtrRanege, 5) : Bid + SL * Point;
        if (TPAtrRanege != 0) tp = Ask - NormalizeDouble(getAtr() * TPAtrRanege, 5);

        // OrderSend( symbol, ordertype, lots[0.01単位], price, slippage[0.1pips],stoploss,takeprofit,comment,magic,expiration,arrow_color);
        res = OrderSend(Symbol(), OP_SELL, LotsOptimized(), Bid, 3, sl, tp, "", MAGICMA, 0, Red);

        if (res == -1) ErrorLog(GetLastError(), "Sell OrderSend error.");
        return;
    }
    /** buy entry ***************************************************************************************************************/
    if (ma_prev.IsStage5() && ma1.IsBuyEntry() && ma2.IsUpTrend() && ma3.IsUpTrend()) {
        sl = SL == 0 ? Ask - NormalizeDouble(getAtr() * SLAtrRanege, 5) : Ask - SL * Point;
        if (TPAtrRanege != 0) tp = Bid + NormalizeDouble(getAtr() * TPAtrRanege, 5);

        res = OrderSend(Symbol(), OP_BUY, LotsOptimized(), Ask, 3, sl, tp, "", MAGICMA, 0, Blue);
        if (res == -1) ErrorLog(GetLastError(), "Buy OrderSend error.");

        return;
    }

    delete ma_prev;
    delete ma1;
    delete ma2;
    delete ma3;
}

/**
 * @brief 決済処理
 */
void CheckForClose()
{
    // 新しいバーの最初のティックのみトレードする
    if (Volume[0] > 1) return;
    double cci = iCCI(NULL, PERIOD_CURRENT, 14, (PRICE_HIGH + PRICE_LOW + PRICE_CLOSE) / 3, 0);
    MovingAverage3Line* ma = createMovingAverage3Line(Symbol(), PERIOD_CURRENT);

    // ポジションの存在チェック
    for (int i = 0; i < OrdersTotal(); i++) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) break;
        if (OrderMagicNumber() != MAGICMA || OrderSymbol() != Symbol()) continue;
        // TODO:発注送信に失敗した場合のリトライをどうするか？WebRequestの場合も考慮する必要がありそう。
        /** sell close ***************************************************************************************************************/
        if (OrderType() == OP_SELL) {
            if (ma.IsSellClose()) {
                if (!OrderClose(OrderTicket(), OrderLots(), Ask, 3, White)) ErrorLog(GetLastError(), "Sell OrderClose error. ");
            }
            break;
        }
        /** buy close ***************************************************************************************************************/
        if (OrderType() == OP_BUY) {
            if (ma.IsBuyClose()) {
                if (!OrderClose(OrderTicket(), OrderLots(), Bid, 3, White)) ErrorLog(GetLastError(), "Buy OrderClose error. ");
            }
            break;
        }
    }
    delete ma;
}

ENUM_TIMEFRAMES getNextHigherTimeFrame(ENUM_TIMEFRAMES timeframe)
{
    ENUM_TIMEFRAMES result;
    switch (timeframe) {
        case PERIOD_M1:
            result = PERIOD_H1;
            break;
        case PERIOD_M5:
            result = PERIOD_H1;
            break;
        case PERIOD_M15:
            result = PERIOD_H1;
            break;
        case PERIOD_M30:
            result = PERIOD_H1;
            break;
        case PERIOD_H1:
            result = PERIOD_H4;
            break;
        case PERIOD_H4:
            result = PERIOD_D1;
            break;
        case PERIOD_D1:
            result = PERIOD_W1;
            break;
        default:
            result = PERIOD_CURRENT;
            break;
    }
    return result;
};

ENUM_TIMEFRAMES get2NextHigherTimeFrame(ENUM_TIMEFRAMES timeframe)
{
    ENUM_TIMEFRAMES result;
    switch (timeframe) {
        case PERIOD_M1:
            result = PERIOD_H4;
            break;
        case PERIOD_M5:
            result = PERIOD_H4;
            break;
        case PERIOD_M15:
            result = PERIOD_H4;
            break;
        case PERIOD_M30:
            result = PERIOD_H4;
            break;
        case PERIOD_H1:
            result = PERIOD_D1;
            break;
        case PERIOD_H4:
            result = PERIOD_W1;
            break;
        case PERIOD_D1:
            result = PERIOD_W1;
            break;
        default:
            result = PERIOD_CURRENT;
            break;
    }
    return result;
};

void ErrorLog(int error_code, string message)
{
    string err_type = error_code <= 150 ? "server error" : "MQL error";
    printf("&s [%s code:%d]%s", message, err_type, error_code, ErrorDescription(error_code));
};

MovingAverage3Line* createMovingAverage3Line(string symbol, int timeframe, int shift = 0)
{
    return new MovingAverage3Line(
        iMA(symbol, timeframe, MovingPeriod1, MovingShift1, MODE_EMA, PRICE_CLOSE, shift),
        iMA(symbol, timeframe, MovingPeriod2, MovingShift2, MODE_EMA, PRICE_CLOSE, shift),
        iMA(symbol, timeframe, MovingPeriod3, MovingShift3, MODE_EMA, PRICE_CLOSE, shift)
    );
};

double getAtr()
{
    return iATR(
        NULL, // 通貨ペア
        _Period, // 時間軸
        20, // 平均期間
        1 // シフト
    );
};
