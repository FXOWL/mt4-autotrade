/**
 * @file FXWOLF01.mq4
 *
 * 月末の特定の時刻にトレードするEA
 *
 * @author fxowl(javajava0708@gmail.com)
 * @brief
 * @version 1.0
 * @date 2023-05-09
 *
 * @copyright Copyright (c) 2023
 *
 */

#property copyright "2023_04, fxowl."
#property link "https://www.mql5.com"
#property version "1.00"
#property strict
#property description "指定した時刻にトレードするEA"

#include <EAStrategy/BollingerBands.mqh>
#include <Tools/DateTimeExt.mqh>
#include <TradeForMT4/AccountInfo.mqh>
#include <stderror.mqh>
#include <stdlib.mqh>

input int MAGICMA = 20230507; // マジックナンバー
input double InpLots = 0.01; // ロット数（0.01=1000通貨）
input int InpSlippage = 4; // スリッページ上限
input double InpSpreadLimit = 10; // スプレッド上限
input double InpTakeProfit = 0.0; // 利益確定幅(pips)
input double InpLossCut = 50.0; // 損切確定幅(pips)

input int InpTradeOpenHour = 10; // トレードのエントリー時刻(ローカルPCの時)
input int InpTradeOpenMin = 0; // トレードのエントリー時刻(ローカルPCの分)
input int InpTradeCloseHour = 12; // トレードをクローズする時刻(ローカルPCの時)
input int InpTradeCloseMin = 35; // トレードをクローズする時刻(ローカルPCの分)
input double InpMaximumRisk = 0.05; // リスクにさらす余剰証拠金の割合(前日の基準)

double spread;
CAccountInfo account;

int OnInit()
{
    if (InputValid() == false) {
        return (INIT_PARAMETERS_INCORRECT);
    }
    return (INIT_SUCCEEDED);
}

/**
 * @brief 入力値を検証する
 *
 * @return true
 * @return false
 */
bool InputValid()
{
    if (InpTradeOpenHour < 0 && InpTradeOpenHour > 23) {
        Print("入力エラー|InpTradeOpenHour に入力できる値は0から23の範囲です。");
        return false;
    };
    if (InpTradeOpenMin < 0 && InpTradeOpenMin > 60) {
        Print("入力エラー|InpTradeOpenMin に入力できる値は0から60の範囲です。");
        return false;
    };
    if (InpTradeCloseHour < 0 && InpTradeCloseHour > 23) {
        Print("入力エラー|InpTradeCloseHour に入力できる値は0から23の範囲です。");
        return false;
    };
    if (InpTradeCloseMin < 0 && InpTradeCloseMin > 60) {
        Print("入力エラー|InpTradeCloseMin に入力できる値は0から60の範囲です。");
        return false;
    };
    return true;
}

void OnTick()
{
    const static double today_profit = calculateTodayProfit();

    // 前日の余剰証拠金とを基に算出した1日あたりの損失上限額
    const static double daily_loss_limit = (account.FreeMargin() - today_profit) * InpMaximumRisk;

    // CExpert ext_trade(account, position,trade);

    bool can_trade = (daily_loss_limit + today_profit) > 0;

    // 取引を行う時間
    CDateTimeExt dt_local;
    dt_local.DateTime(TimeLocal());
    dt_local.Hour(InpTradeOpenHour);
    dt_local.Min(InpTradeOpenMin);
    dt_local.Sec(0);
    dt_local.AtEndOfMonth();

    CDateTimeExt dt_srv_start = dt_local.ToMtServerStruct();
    CDateTimeExt dt_srv_end = dt_local.ToMtServerStruct();
    dt_srv_end.HourInc(InpTradeCloseHour - InpTradeOpenHour);

    CDateTimeExt now;
    datetime dt_now = IsTesting() ? TimeLocal() : TimeCurrent();

    now.DateTime(TimeCurrent());
    now.Min(0);
    now.Sec(0);

    if (CalculateCurrentOrders() == 0 && checkSpred(InpSpreadLimit) && can_trade && now.DateTime() == dt_srv_start.DateTime())
        OrderOpen(OP_SELL);

    if (CalculateCurrentOrders() > 0 && checkSpred(InpSpreadLimit) && can_trade && now.DateTime() == dt_srv_end.DateTime())
        OrderOpen(OP_BUY);
}

/**
 * @brief トレード時のスプレッドが設定した値を超えていないかをチェック
 *
 * @return bool
 */
bool checkSpred(double spredLimit)
{
    if (GetSpread() < spredLimit) return true;

    Print(
        "市場のスプレッド値が上限値を超えています。| 設定値:" + (string)spredLimit + "pips | 発注時スプレッド:" + (string)GetSpread() +
        "pips"
    );
    return false;
}

/** 現在のスプレッド値を取得する
 * @brief Get the Spread object
 * MarketInfo(NULL, MODE_SPREAD)と同じ結果だが、MarketInfoはブローカーから受信するため遅延することがある。
 * スキャル等の場合はこのメソッドの仕様を推奨する
 * @return double
 */
double GetSpread() { return (Ask - Bid) / Point; }

double calculateTodayProfit()
{
    int total = OrdersHistoryTotal();
    double todayProfit = 0.0;
    datetime todayStart = iTime(_Symbol, PERIOD_D1, 0); // 当日の開始時刻を取得
    for (int i = total - 1; i >= 0; i--) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_HISTORY) == false) continue;

        datetime closeTime = OrderCloseTime();
        if (closeTime < todayStart) break;
        double profit = OrderProfit();
        todayProfit += profit;
    }
    return todayProfit;
}

void OrderOpen(int order_type)
{
    const static int MAX_RETRIES = 5;
    int res;
    int count_retries;
    for (count_retries = 0; count_retries < MAX_RETRIES; count_retries++) {
        if (order_type == OP_BUY) {
            res = OrderSend(
                Symbol(), OP_BUY, InpLots, Ask, InpSlippage, Bid - InpLossCut * Point * 10, Ask + InpTakeProfit * Point * 10, "", MAGICMA,
                0, Red
            );
        }
        else {
            res = OrderSend(
                Symbol(), OP_SELL, InpLots, Bid, InpSlippage, Ask + InpLossCut * Point * 10, Bid - InpTakeProfit * Point * 10, "", MAGICMA,
                0, Blue
            );
        }
        if (res == -1) { // オーダーエラー
            int errorcode = GetLastError(); // エラーコード取得

            if (errorcode != ERR_NO_ERROR) { // エラー発生
                printf("エラーコード:%d , 詳細:%s ", errorcode, ErrorDescription(errorcode));

                if (errorcode == ERR_TRADE_NOT_ALLOWED) { // 自動売買が許可されていない
                    MessageBox(ErrorDescription(errorcode), "オーダーエラー", MB_ICONEXCLAMATION);
                    return;
                }
            }

            Sleep(1000); // 1000msec待ち
            RefreshRates(); // レート更新
            double order_entry_price = Ask; // 更新した買値でエントリーレートを再設定
            printf("再エントリー要求回数:%d, 更新エントリーレート:%g", count_retries + 1, order_entry_price);
        }
        else { // 注文約定
            Print("新規注文約定。 チケットNo=", res);
            Sleep(300); // 300msec待ち(オーダー要求頻度が多過ぎるとエラーになる為)

            // エントリー中ポジションの注文変更
            // LimitStop_Set(res);
            break;
        }
    }
}

int CalculateCurrentOrders()
{
    int positions = 0;
    for (int i = 0; i < OrdersTotal(); i++) {
        if (OrderSelect(i, SELECT_BY_POS, MODE_TRADES) == false) break;
        if (OrderSymbol() == Symbol() && OrderMagicNumber() == MAGICMA) {
            positions++;
        }
    }

    return positions;
}

void Log(string message, int error_code)
{
    string err_type = error_code <= 150 ? "Server error" : "MQL error";
    printf("&s [%s code:%d]%s", message, err_type, error_code, ErrorDescription(error_code));
};
