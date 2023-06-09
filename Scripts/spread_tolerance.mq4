//+------------------------------------------------------------------+
//|                                             spread_tolerance.mq4 |
//|                                                    naoya hiyoshi |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "naoya hiyoshi"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict
#property script_show_inputs
//--- input parameters
//最小許容スプレッドを格納する変数
input double   maxSpred=2.0;

//OnTick関数内でスプレッドを取得し、最小許容スプレッドを下回っている場合はエラーを出力する
void OnTick()
{
    double currentSpread = Ask - Bid; //現在のスプレッドを取得する
    if(currentSpread < maxSpred) //最小許容スプレッドを下回っている場合
    {
        Print("注文は最小許容スプレッド(" + maxSpred + ")以上でなければなりません。現在のスプレッドは" + currentSpread + "です。"); //エラーメッセージを出力する
        return; //注文を中断する
    }
    //注文を出す処理を続ける
}

//外部から許容スプレッドを設定するための関数
//void SetMaxSpread(double spread)
//{
//    max_spred = spread; //最小許容スプレッドの値を更新する
//}
