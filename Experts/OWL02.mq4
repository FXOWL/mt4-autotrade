//+------------------------------------------------------------------+
//|                                                        OWL02.mq4 |
//|                                      Copyright 2023-2023, fxowl. |
//|                                              http://www.mql4.com |
//+------------------------------------------------------------------+
/**
 * @file OWL02.mq4
 *
 * 日時指定のトレード
 *
 * @author fxowl(javajava0708@gmail.com)
 * @brief
 * @version 0.1
 * @date 2023-04-26
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

input int MAGICMA = 20230427; // マジックナンバー
input double InpLots = 0.01; // ロット数（0.01=1000通貨）
input int InpSlippage = 4; // スリッページ上限
input double InpSpreadLimit = 10; // スプレッド上限
input double InpTakeProfit = 10.0; // 利益確定幅(pips)
input double InpLossCut = 10.0; // 損切確定幅(pips)
input int InpRsiPeriod = 5; // RSI期間
input ENUM_APPLIED_PRICE InpRsiAppliedPrice = PRICE_CLOSE; // RSI適用価格
input int InpOverboughtLine = 85; // RSIで買われすぎと判定する％
input int InpOversoldLine = 20; // RSIで売られすぎと判定する％
input int InpTradeTime = 7; // トレードを行う時間(ローカルPCの時刻)
input double InpMaximumRisk = 0.05; // リスクにさらす余剰証拠金の割合(前日の基準)

double spread;
CAccountInfo account;

int OnInit() { return (INIT_SUCCEEDED); }

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
    dt_local.Hour(InpTradeTime);
    CDateTimeExt dt_srv = dt_local.ToMtServerStruct();

    if (CalculateCurrentOrders() == 0 && checkSpred(InpSpreadLimit) && can_trade && dt_srv.hour == TimeHour(Time[1])) CheckForOpen();
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
double GetSpread()
{
    // ブローカーの価格の桁数が2桁・4桁の場合
    // return (Ask - Bid) / (Point * 10);
    // ブローカーの価格の桁数が3桁・5桁の場合
    // double res = Ask - Bid;
    // Print("debug Ask - Bid" + (string)res); //0.008
    // Print("debug Point" + (string)Point); //0.001
    return (Ask - Bid) / Point;
}

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

void CheckForOpen()
{
    // BollingerBands* bb = createBollingerBands((ENUM_TIMEFRAMES)_Period);

    int res;
    double rsi = iRSI(Symbol(), 0, InpRsiPeriod, InpRsiAppliedPrice, 1);

    if (rsi < InpOversoldLine) {
        res = OrderSend(
            Symbol(), OP_BUY, InpLots, Ask, InpSlippage, Bid - InpLossCut * Point * 10, Ask + InpTakeProfit * Point * 10, "", MAGICMA, 0,
            Red
        );
    }
    if (rsi > InpOverboughtLine) {
        res = OrderSend(
            Symbol(), OP_SELL, InpLots, Bid, InpSlippage, Ask + InpLossCut * Point * 10, Bid - InpTakeProfit * Point * 10, "", MAGICMA, 0,
            Blue
        );
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

void ErrorLog(int error_code, string message)
{
    string err_type = error_code <= 150 ? "server error" : "MQL error";
    printf("&s [%s code:%d]%s", message, err_type, error_code, ErrorDescription(error_code));
};

BollingerBands* createBollingerBands(ENUM_TIMEFRAMES timeframe) { return new BollingerBands(timeframe); };

/**
 * @brief 資金管理クラス
 *
 * 口座の資金を取得し、20%
 */
// class MoneyManagement()
// {
//     //    private:
//     //     /* data */
//    public:
//     MoneyManagement(/* args */);
//     // ~MoneyManagement();
// };

// MoneyManagement::MoneyManagement(/* args */) {}

// MoneyManagement::~MoneyManagement() {}

// class Position()
// {
//    private:
//     /* data */
//    public:
//     Position(/* args */);
//     ~Position();
// };

// Position::Position(/* args */) {}

// Position::~Position() {}

// class Trade()
// {
//    private:
//     /* data */
//    public:
//     Trade(/* args */);
//     ~Trade();
// };

// Trade::Trade(/* args */) {}

// Trade::~Trade() {}
