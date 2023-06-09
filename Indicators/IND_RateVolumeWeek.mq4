//+------------------------------------------------------------------+
//|                                             IND_RateVolumeWeek.mq4 
//|                                 Copyright 2019, Created by Yuki. 
//|                                       http://yukifx.web.fc2.com/ 
//+------------------------------------------------------------------+
//| date:        Ver:    detail
//| 19/04/16    1.00    new
//| 20/02/26    1.01    公開用に調整
//|                                                                  
//+------------------------------------------------------------------+
#property copyright "Copyright 2019, Created by Yuki."
#property link      "http://yukifx.web.fc2.com/"
#property version   "1.00"
#property strict
#property description    "過去2週間分の価格帯別出来高を表示します。GMT設定はGMT+2 (DST：GMT+3)固定です。"
#property description    "15分足のヒストリカルデータが必要になります。"
#property description    "CFDには対応していません(CFDは取引時間がFXと異なるのと、業者によってCFDのシンボル表示が違う為)"
#property description    "元々公開するつもりは無かった適当に作ったインジケータなので雑な作りになっています"


void CommentHeader___________________________________(void){}                                // リストセパレーター


#property indicator_chart_window
#property copyright        "2019, Created by Yuki."

#define OBJ_HEAD    "RateVolWeek_"

#define COMMON_DEBUG_INPUT 0
#define COMMON_MODIFY_GMT 0

#include    <local\\local_common_jpntime.mqh>        // タイムサーバー調整
#include    <local\\local_common.mqh>

#define MARKETARR_MAX   6

static int Market_time[MARKETARR_MAX]    = { 23 , 0 };

enum e_days {
    E_DAY0            = 0 ,    // 当日
    E_DAY1                ,    // 1日前
    E_DAY2                ,    // 2日前
    E_DAY3                ,    // 3日前
    E_DAY4                ,    // 4日前
    E_DAY5                ,    // 5日前
    E_DAY6                ,
    E_DAY7                ,
    E_DAY8                ,
    E_DAY9                ,
    E_DAY10               ,
    E_DAYALL              ,    // 全体
    E_DMAX                     // max
};

struct StGetRowData {        // 取得データ
    double    get_high;
    double    get_low;
    long      get_volume;

    long      unit_volume;      // 平滑出来高
    double    base_rate;        // 基準レート
    int       div_count;        // 分割数
};

struct StRateVolData{           // 価格帯別出来高
    double    rate;
    long      sum_volume;
    double    width_per;        // max_sum_volumeが確定してから算出
};

struct StSetCalData{            // 日別データ
    datetime start_time;
    datetime end_time;
    int      start_dow;
    int      start_DispIndex;
    int      start_M5index;
    int      end_M5index;

    double   max_high;          // 最高値
    double   min_low;           // 最安値
    int      div_count;         // 価格帯分割数
    long     max_sum_volume;    // 出来高サマリ最大値(日別は全共通、全体は全体用)
    bool     done_set;          // 設定済み(当日と全体のみ毎回再更新する)
};

#define POOL_SIZE_PACK      100
#define DAYARRAY            (12*24)
#define ONE_DAY_TIME        ( 3600*24 )
#define SET_PERIOD          PERIOD_M15
#define DIGIT_TIMES         MathPow(10 , Digits - 1)


static StGetRowData     _StGetRowData[DAYARRAY][E_DMAX];        // 生データ
static StRateVolData    _StRateVolData[][E_DAYALL];             // 価格帯別出来高(日別用)
static StRateVolData    _StRateVolAllData[];                    // 価格帯別出来高(全体用)
static StSetCalData     _StSetCalData[E_DMAX];                  // 価格帯別出来高設定データ

int          G_array_dst;
st_jpntime   G_Last_time;
double       G_BaseBarDiff;
color        SetLowColor   = clrGray;
color        SetOverColor  = clrWhite;
color        SetOver2Color = clrMagenta;
color        SetTextColor  = clrWhite;

color        GetBackColor  = clrWhite;

double        G_POINT            = Point() * 10;

string        FileSymbol        = Symbol();

double        G_TIMES_PIP        = 1;

sinput    bool _GBool_DispDailyRateVolume = true;                 // 日毎の価格帯別出来高表示
sinput    bool _GBool_DispAllRateVolume   = true;                 // 全体の価格帯別出来高表示

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//|------------------------------------------------------------------|
int OnInit() {

    if ( _GBool_DispAllRateVolume == true ) {
        ChartSetInteger( 0 , CHART_SHIFT , true ); // チャートの右端をシフト
    }

    GetBackColor = (color)ChartGetInteger( 0 , CHART_COLOR_BACKGROUND , 0);
    if ( GetBackColor == clrWhite ) {
        SetTextColor    = clrBlack;
        SetOverColor    = clrGray;
        SetOver2Color   = clrRed;
        SetLowColor     = clrSilver;
    }

    if ( Period() < PERIOD_M15 || Period() >= PERIOD_D1 ) {
        printf("15分足以上 ～ 日足未満でのみ動作します");
    }


    G_POINT = Point() * 10 * G_TIMES_PIP;

    EventSetTimer(5);                                // OnTimerセット[分解能:1sec]

    ObjectsDeleteAll(0, OBJ_HEAD);


    // サマータイム判定は現在時間で確定させる
    Calculate_JpnTime(0);
    if ( G_Last_time.dst == true ) {
        G_array_dst = 0;
    } else {
        G_array_dst = 1;
    }

    SetData();

    return(0);
}


//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {

    ObjectsDeleteAll(0, OBJ_HEAD);
    EventKillTimer();

}

int TimerCount = 0;
//+------------------------------------------------------------------+
//| OnTimer
//+------------------------------------------------------------------+
void OnTimer() {
    // 5sec毎に処理

    // 起動直後は数秒間強制再描画
    if ( TimerCount <= 3 || CheckHistory() == false ) {
        ObjectsDeleteAll(0, OBJ_HEAD);
        ClearDoneSet();
        SetData();
    }


    TimerCount++;

    if ( TimerCount > 20 && CheckHistory() == true ) {
        EventKillTimer();
    }
}

//+------------------------------------------------------------------+
//| チャートイベント
//+------------------------------------------------------------------+
void OnChartEvent(
                 const int id,          // イベントID
                 const long& lparam,    // long型イベント
                 const double& dparam,  // double型イベント
                 const string& sparam)  // string型イベント
{

    if ( id == CHARTEVENT_CHART_CHANGE ) {     // チャート変更検出
        SetData();                             // 再描画
    }

}


//+------------------------------------------------------------------+
//| ClearDoneSet
//+------------------------------------------------------------------+
void ClearDoneSet(){

    int temp_arr;

    for( int icount = 0 ; icount < (int)E_DAYALL; icount ++) {

        temp_arr = ArrayRange( _StRateVolData , 0 );
        for ( int scount = 0; scount < temp_arr ; scount++) {
            _StRateVolData[scount][icount].rate = 0;
            _StRateVolData[scount][icount].sum_volume = 0;
            _StRateVolData[scount][icount].width_per = 0;
        }

        _StSetCalData[icount].done_set = false;
        _StSetCalData[icount].div_count = 0;
    }

    temp_arr = ArrayRange( _StRateVolAllData , 0 );
    for ( int scount = 0; scount < temp_arr ; scount++) {
        _StRateVolAllData[scount].rate = 0;
        _StRateVolAllData[scount].sum_volume = 0;
        _StRateVolAllData[scount].width_per = 0;
    }


}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{

    static  datetime lasttime;
            datetime temptime;


    temptime        = iTime(NULL,SET_PERIOD,0);

    if ( temptime > (lasttime + 60 * PERIOD_M15) ) {        // 15分以上経過時にtrue
        lasttime = temptime;

        SetData();
    } else {
        Sleep( 1000 * 60 );                                 // 処理が重いので15分経過で再描画して、待機期間中はスリープさせる
    }




    return( rates_total );
}

//+------------------------------------------------------------------+
//| CheckHistory
//+------------------------------------------------------------------+
bool CheckHistory() {

    bool ret = true;
    int  check_index = _StSetCalData[E_DAY1].start_DispIndex;
    int get_index = iBarShift( Symbol() , Period() , _StSetCalData[E_DAY1].start_time , false); // 無い場合は直近
    
    if ( check_index > 0 && get_index > 0) {
        int diff_index = MathAbs(check_index - get_index);
        if ( diff_index > 10 ) {
            ret = false;
            //printf( "Reset[%d]%d %d" , __LINE__ , get_index , check_index );
        }
    }
    //printf( "[%d]%d %d" , __LINE__ , get_index , check_index );
    
    return ret;
}

//+------------------------------------------------------------------+
//| SetData
//+------------------------------------------------------------------+
void SetData(){

    datetime ustime     = Time[0];
    int      check_hour = Market_time[G_array_dst];
    string   strtime    = StringFormat( "%s %02d:00" , TimeToStr(ustime , TIME_DATE) , check_hour );
    datetime basetime   = StrToTime(strtime);
    datetime endtime    = iTime(Symbol(),SET_PERIOD,0);

    int check_index     = iBarShift( Symbol() , Period() , basetime , false); // 無い場合は直近
    datetime check_time = iTime(Symbol() , Period() , check_index );

    if ( TimeDay(check_time) != TimeDay(basetime) && check_index > 0) {
        // CFDは取引時間が若干違う
        check_time    = iTime(Symbol() , Period() , check_index - 1 );
        basetime = check_time;
    }

    _StSetCalData[E_DAY0].start_time = AdjustDate(basetime , true , 0);
    _StSetCalData[E_DAY0].end_time   = endtime;

    for ( int icount = 0; icount < E_DAYALL ; icount++ ) {

        if ( icount >= 1) {
            datetime set_time = _StSetCalData[icount -1].start_time - ONE_DAY_TIME;

            _StSetCalData[icount].start_time     = AdjustDate( set_time , true , icount);
            _StSetCalData[icount].end_time       = AdjustDate(_StSetCalData[icount].start_time + ONE_DAY_TIME , false , icount);
        }
        _StSetCalData[icount].start_DispIndex    = iBarShift( Symbol() , Period() , _StSetCalData[icount].start_time , false); // 無い場合は直近

        int startdow    = TimeDayOfWeek( _StSetCalData[icount].start_time );
        int enddow      = TimeDayOfWeek( _StSetCalData[icount].end_time );
        _StSetCalData[icount].start_dow = startdow;

        string debug_str = StringFormat("[%d]%d %s%s - %s%s" 
                , __LINE__ , icount 
                ,TimeToStr(_StSetCalData[icount].start_time) 
                , DOWSTR[startdow]
                ,TimeToStr(_StSetCalData[icount].end_time) 
                , DOWSTR[enddow]
                );

//        Print(debug_str);

        GetRowOHLC( (e_days)icount);

    }
    SetCalAllHighLow();        // GetRowOHLCの後に呼ぶ


    for ( int icount = 0; icount <= E_DAYALL ; icount++ ) {
        SetCalRate((e_days)icount);        // SetCalAllHighLowの後に呼ぶ
    }

    SetInitArray();
    for ( int icount = 0; icount < E_DAYALL ; icount++ ) {
        if ( icount != (int)E_DAYALL ) {
            SetCalVolume((e_days)icount);    // SetCalRateの後に呼ぶ(全DAY設定後に行う為、ループは一緒に出来ない)
        }
    }
    SetCal_DayMaxVolume();                    // SetCalVolume全算出後に呼ぶ

    for ( int icount = 0; icount <= E_DAYALL ; icount++ ) {
        SetCal_WidthPer((e_days)icount);    // SetCal_DayMaxVolumeの後に呼ぶ
        Disp_Vol_ALL((e_days)icount);        // SetCal_WidthPerの後に呼ぶ
    }


}


//+------------------------------------------------------------------+
//| GetRowOHLC
//+------------------------------------------------------------------+
void GetRowOHLC(e_days in_days){
    

    if ( in_days != E_DAY0 ) {
        if ( _StSetCalData[in_days].div_count > 0 ) {
            // 当日以外は算出済みの場合は、取得しない
            return;
        }
    }

    _StSetCalData[in_days].start_M5index = iBarShift( Symbol() , SET_PERIOD , _StSetCalData[in_days].start_time , false); // 無い場合は直近
    _StSetCalData[in_days].end_M5index   = iBarShift( Symbol() , SET_PERIOD , _StSetCalData[in_days].end_time , false); // 無い場合は直近
    
    int diff_index = _StSetCalData[in_days].start_M5index - _StSetCalData[in_days].end_M5index;
    int get_index;
    
    
    double temp_high;
    double temp_low;
    double cal_high;
    double cal_low;
    long   get_volume;
    int    temp_div;
    
    double max_high = 0;
    double min_low  = 0;
    
    double temp_times = DIGIT_TIMES;

    int get_array_size = ArrayRange( _StGetRowData , 0);
    
    for ( int icount = 0 ; icount < diff_index ; icount++) {
        if ( icount > DAYARRAY) {
            break;
        }
        get_index   = _StSetCalData[in_days].end_M5index  + icount;
        temp_high   = iHigh(    Symbol() , SET_PERIOD , get_index );
        temp_low    = iLow(     Symbol() , SET_PERIOD , get_index );
        get_volume  = iVolume(  Symbol() , SET_PERIOD , get_index );

        // 0.1pips以下は四捨五入
        cal_high    = MathRound(temp_high * temp_times) / temp_times;
        cal_low     = MathRound(temp_low  * temp_times) / temp_times;

        temp_div = (int)((cal_high - cal_low) * temp_times) + 1;
        if ( temp_div <= 0) {
            temp_div = 1;
        }

        if ( max_high <= 0) {
            max_high = cal_high;
        }
        if ( min_low <= 0 ) {
            min_low = cal_low;
        }

        if ( max_high < cal_high ) {
            max_high = cal_high;
        }
        if ( min_low > cal_low ) {
            min_low = cal_low;
        }

        if ( get_array_size > icount ) {
            _StGetRowData[icount][in_days].get_high     = temp_high;
            _StGetRowData[icount][in_days].get_low      = temp_low;
            _StGetRowData[icount][in_days].base_rate    = cal_low;
            _StGetRowData[icount][in_days].div_count    = temp_div;
            _StGetRowData[icount][in_days].unit_volume  = get_volume / temp_div;
            _StGetRowData[icount][in_days].get_volume   = get_volume;
        }


//        if ( icount < 50) {
//            printf( "[%d]%f %f %d %d %d %f" , __LINE__ ,cal_high , cal_low 
//                , get_volume
//                , _StGetRowData[get_index][in_days].unit_volume
//                , temp_div
//                , temp_times
//                );
//        }

//        datetime check_time = iTime( Symbol() , SET_PERIOD , get_index );
//        printf("[%d]%d %d %f %s %d" , __LINE__ , icount , get_index , _StGetRowData[get_index][in_days].get_high , TimeToStr(check_time) , diff_index );
    }

    if ( min_low > 0) {
        _StSetCalData[in_days].max_high = max_high;
        _StSetCalData[in_days].min_low    = min_low;
        _StSetCalData[in_days].div_count = (int)(1 + (max_high - min_low) * temp_times);

        AddPool( _StSetCalData[in_days].div_count , in_days);
    }
    
//    printf( "[%d]%d %f %f %d %f" , __LINE__ , in_days , max_high , min_low , _StSetCalData[in_days].div_count , min_low );
}

//+------------------------------------------------------------------+
//| SetCalAllHighLow
//+------------------------------------------------------------------+
void SetCalAllHighLow() {
    
    double max_high = 0;
    double min_low = 0;
    double now_high;
    double now_low;

    for( int icount = 0 ; icount < (int)E_DAYALL ; icount++ ) {
        now_high = _StSetCalData[icount].max_high;
        now_low  = _StSetCalData[icount].min_low;

        if ( max_high <= 0) {
            max_high = now_high;
        }
        if ( min_low <= 0 ) {
            min_low = now_low;
        }

        if ( max_high < now_high ) {
            max_high = now_high;
        }
        if ( min_low > now_low ) {
            min_low = now_low;
        }

    }

    _StSetCalData[E_DAYALL].max_high = max_high;
    _StSetCalData[E_DAYALL].min_low  = min_low;

    if ( min_low > 0) {
        _StSetCalData[E_DAYALL].div_count = (int)(1 + (max_high - min_low) * DIGIT_TIMES);

        // printf( "[%d]%f %f %d" , __LINE__ , max_high , min_low , _StSetCalData[E_DAYALL].div_count );

        // 動的メモリを確保
        AddPool( _StSetCalData[E_DAYALL].div_count , E_DAYALL);
    }

}

//+------------------------------------------------------------------+
//| SetCalRate
//+------------------------------------------------------------------+
void SetCalRate( e_days in_days ){
    // 動的配列にレートを設定する

    int     array_max    ;
    double  base_rate;
    bool    set_bool = true;

    array_max        = _StSetCalData[in_days].div_count;
    base_rate        = _StSetCalData[in_days].min_low;
    if ( in_days != E_DAYALL ) {
        if ( in_days != E_DAY0 ) {
            if ( _StSetCalData[in_days].done_set == true) {
                set_bool = false;
            }
        }

        if ( set_bool == true ) {
            for( int icount = 0 ; icount < array_max; icount++ ) {
                _StRateVolData[icount][in_days].rate = base_rate + icount * G_POINT;
                //printf( "[%d]%d %f" , __LINE__ , icount , _StRateVolData[icount][in_days].rate );
            }
        }
    } else {
        for( int icount = 0 ; icount < array_max; icount++ ) {
            _StRateVolAllData[icount].rate = base_rate + icount * G_POINT;
            //printf( "[%d]%d %f" , __LINE__ , icount , _StRateVolAllData[icount].rate );
        }
    }
}

//+------------------------------------------------------------------+
//| SetInitArray
//+------------------------------------------------------------------+
void SetInitArray(){
    
    int        now_size;
    now_size = ArrayRange( _StRateVolData , 0 );

    for( int icount = 0; icount < now_size ; icount ++ ) {
        _StRateVolData[icount][(int)E_DAY0].sum_volume = 0;
    }

    now_size = ArrayRange( _StRateVolAllData , 0 );

    for( int icount = 0; icount < now_size ; icount ++ ) {
        _StRateVolAllData[icount].sum_volume = 0;
    }
    
}

//+------------------------------------------------------------------+
//| SetCalVolume
//+------------------------------------------------------------------+
void SetCalVolume( e_days in_days ){
    // 動的配列に出来高を設定する

    int temp_days = (int)in_days;
    int set_index = 0;
    int set_all_index = 0;

    long max_day_volume = 0;
    static long max_allday_volume = 0;
    long get_volume;
    bool set_bool = true;

    if ( in_days != E_DAYALL ) {
        // 分足分ループ
        for( int time_count = 0 ; time_count < DAYARRAY; time_count++ ) {
            double base_rate    = _StGetRowData[time_count][temp_days].base_rate;
            int    max_array    = _StGetRowData[time_count][temp_days].div_count;
            long   set_volume   = _StGetRowData[time_count][temp_days].unit_volume;

            // 生データ配列分ループ
            for ( int icount = 0; icount < max_array ; icount++ ) {

                if ( in_days != E_DAY0 ) {
                    if ( _StSetCalData[in_days].done_set == true) {
                        set_bool = false;
                    }
                }

                double set_rate = base_rate + G_POINT * icount;
                if ( set_bool == true ) {
                    set_index = FindRateVolumeArrayIndex( in_days , set_rate);
                    if ( set_index < 0 ) {
                        //printf( "[%d]DaysErr %d %d %f" , __LINE__ , icount , set_index , set_rate );
                    } else {
                        _StRateVolData[set_index][temp_days].sum_volume += set_volume;
                        get_volume = _StRateVolData[set_index][temp_days].sum_volume;
                        if ( get_volume > max_day_volume ) {
                            max_day_volume = get_volume;
                        }
                    }
                }

                set_all_index = FindRateVolumeArrayIndex( E_DAYALL , set_rate);
                if ( set_all_index < 0 ) {
                    //printf( "[%d]AllErr %d %d %f" , __LINE__ , icount , set_all_index , set_rate );
                } else {
                    _StRateVolAllData[set_all_index].sum_volume += set_volume;
                    get_volume = _StRateVolAllData[set_all_index].sum_volume;
                    if ( get_volume > max_allday_volume ) {
                        max_allday_volume = get_volume;
                    }
                }
            }

        }
    }

    if ( max_day_volume > 0) {
        _StSetCalData[temp_days].max_sum_volume = max_day_volume;
        _StSetCalData[temp_days].done_set = true;
    }
    if ( max_allday_volume > _StSetCalData[(int)E_DAYALL].max_sum_volume ) {
        _StSetCalData[(int)E_DAYALL].max_sum_volume = max_allday_volume;
    }

}

//+------------------------------------------------------------------+
//| SetCal_DayMaxVolume
//+------------------------------------------------------------------+
void SetCal_DayMaxVolume( ){

    long max_day_volume = 0;
    for ( int icount = 0 ; icount < (int)E_DAYALL ; icount++ ) {
        if ( _StSetCalData[icount].max_sum_volume > max_day_volume ) {
            max_day_volume = _StSetCalData[icount].max_sum_volume;
        }
    }

    if ( max_day_volume > 0 ) {
        for ( int icount = 0 ; icount < (int)E_DAYALL ; icount++ ) {
            _StSetCalData[icount].max_sum_volume = max_day_volume;
            //printf("%d %d %d" , icount , _StSetCalData[icount].max_sum_volume , _StSetCalData[(int)E_DAYALL].max_sum_volume);
        }
    }
}

//+------------------------------------------------------------------+
//| SetCal_WidthPer
//+------------------------------------------------------------------+
void SetCal_WidthPer( e_days in_days ){

    // 毎回再計算する

    int temp_days = (int)in_days;
    double temp_per = 0;

    for( int icount = 0; icount < _StSetCalData[in_days].div_count; icount++ ) {
        if ( in_days != E_DAYALL ) {
            long   get_volume    = _StRateVolData[icount][temp_days].sum_volume;
            if ( _StSetCalData[in_days].max_sum_volume > 0 ) {
                temp_per = (100 * (double)get_volume / (double)_StSetCalData[in_days].max_sum_volume);
                _StRateVolData[icount][temp_days].width_per = temp_per;

                //printf( "[%d]%d %d %f " , __LINE__ , get_volume , _StSetCalData[in_days].max_sum_volume , temp_per );
            }
        } else {
            long   get_volume    = _StRateVolAllData[icount].sum_volume;
            if ( _StSetCalData[in_days].max_sum_volume > 0 ) {
                temp_per = (100 * (double)get_volume / (double)_StSetCalData[in_days].max_sum_volume);
                _StRateVolAllData[icount].width_per = temp_per;

//                printf( "[%d]%d %d %f " , __LINE__ , get_volume , _StSetCalData[in_days].max_sum_volume , temp_per );
            }
        }
    }
}

//+------------------------------------------------------------------+
//| FindRateVolumeArrayIndex
//+------------------------------------------------------------------+
int FindRateVolumeArrayIndex( e_days in_days , double in_rate ){

    int ret_index = -1;

    int array_max    = _StSetCalData[in_days].div_count;
    double base_rate = _StSetCalData[in_days].min_low;
    int diff_rate    = 0;

    if ( in_days != E_DAYALL ) {
        for( int icount = 0 ; icount < array_max; icount++ ) {
            diff_rate =  (int)(MathAbs(_StRateVolData[icount][in_days].rate - in_rate) * DIGIT_TIMES);
            if ( diff_rate == 0 ) {
                ret_index = icount;
                break;
            }
        }
    } else {
        for( int icount = 0 ; icount < array_max; icount++ ) {
            diff_rate =  (int)(MathAbs(_StRateVolAllData[icount].rate - in_rate) * DIGIT_TIMES);
            if ( diff_rate == 0 ) {
                ret_index = icount;
                break;
            }
        }
    }

    return ret_index;
}

//+------------------------------------------------------------------+
//| AddPool
//+------------------------------------------------------------------+
bool AddPool( int in_size , e_days in_days ) {
    
    bool    tempret = false;
    int     now_size;
    int     set_size = POOL_SIZE_PACK;
    
    if ( in_size > 0 ) {
        if ( set_size < in_size) {
            set_size = in_size + 1;
        }

        if ( in_days != E_DAYALL ) {
            now_size = ArrayRange( _StRateVolData , 0 );
            if ( now_size < set_size ) {
                tempret = ArrayResize( _StRateVolData , set_size , set_size + POOL_SIZE_PACK );
            }
        } else {
            now_size = ArrayRange( _StRateVolAllData , 0 );
            if ( now_size < set_size ) {
                tempret = ArrayResize( _StRateVolAllData , set_size , set_size + POOL_SIZE_PACK );
            }
        }
    }

    //printf( "[%d]%d %d %d " , __LINE__ , in_days , in_size , now_size );
    
    return tempret;
}


//+------------------------------------------------------------------+
//| AdjustDate
//+------------------------------------------------------------------+
datetime AdjustDate( datetime in_time , bool in_start , int in_daycount ){

    int         tempdow;
    datetime    ret_time = in_time;

    tempdow        = TimeDayOfWeek( ret_time );
    if ( tempdow == SUNDAY ) {
        ret_time -= ONE_DAY_TIME;
    }

    if ( in_start == true) {
        tempdow        = TimeDayOfWeek( ret_time );
        if ( tempdow == SATURDAY ) {
            ret_time -= ONE_DAY_TIME;
        } 
    }

    // 出来高0対策
    datetime temp_base     = ret_time;
    datetime adjust_time;
    int check_index        = iBarShift( Symbol() , Period() , temp_base , false); // 無い場合は直近
    datetime check_time    = iTime(Symbol() , Period() , check_index );

    if ( TimeDay(temp_base) != TimeDay(check_time) ) {
        if ( temp_base > check_time ) {
            adjust_time = iTime(Symbol() , Period() , check_index - 1 );
        } else {
            adjust_time = iTime(Symbol() , Period() , check_index + 1 );
        }
        ret_time = adjust_time;

//        if ( in_start == true ) {
//            int s_dow = TimeDayOfWeek(temp_base);
//            int c_dow = TimeDayOfWeek(check_time);
//            int e_dow = TimeDayOfWeek(adjust_time);
//            printf( "[%d] %s[%s] - %s[%s} %s[%s} %d" , __LINE__ 
//                ,  TimeToStr(temp_base)  , str_dow[s_dow] 
//                ,  TimeToStr(check_time) , str_dow[c_dow] 
//                , TimeToStr(adjust_time) , str_dow[e_dow] 
//                , in_start);
//        }
    }

    return ret_time;
}

//+------------------------------------------------------------------+
//| Disp_Vol_ALL
//+------------------------------------------------------------------+
void Disp_Vol_ALL( e_days in_day ) {

    int       max_arr        = _StSetCalData[in_day].div_count;
    datetime disp_start_time = _StSetCalData[in_day].start_time;
    int      disp_start_index = iBarShift( Symbol() , Period() , disp_start_time , false); // 無い場合は直近;
    G_BaseBarDiff    = (double)ChartGetInteger( 0,CHART_WIDTH_IN_BARS,0 ) - ChartGetInteger( 0,CHART_FIRST_VISIBLE_BAR,0 );


    if ( disp_start_index > 0 ) {
        for ( int icount = 0; icount < max_arr; icount++ ) {
            Disp_MarketDepth_Single( in_day , icount , disp_start_index);

        }

        //printf( "[%d]%d %d" , __LINE__ , (int)in_day , disp_start_index );

        DispDailyLine( in_day    , disp_start_index );
    }
    
}


//+------------------------------------------------------------------+
//| GetDispMaxWidth
//+------------------------------------------------------------------+
int GetDispMaxWidth( ){
    int ret = 0;

    ret = 24 * 60 / Period();

    return ret;
}

//+------------------------------------------------------------------+
//| Disp_MarketDepth_Single
//+------------------------------------------------------------------+
void Disp_MarketDepth_Single( e_days in_day , int in_index , int start_index ) {

    if ( _GBool_DispDailyRateVolume == false ) {
        if ( in_day < E_DAYALL ) {
            return;
        }
    }

    if ( _GBool_DispAllRateVolume == false ) {
        if ( in_day == E_DAYALL ) {
            return;
        }
    }

    string     obj_name = StringFormat( "%s_RVol2_%d_%d" , OBJ_HEAD , in_day , in_index);
    int        offset_baseindex    = 0;
    int        offsetindex         = 0;
    double     temp_rate;
    double     disp_volume         = 0;
    double     temp_per            = 0;
    color      set_color           = SetLowColor;
    datetime   base_time           = Time[start_index];

    if ( in_day != E_DAYALL ) {
        temp_rate        = _StRateVolData[in_index][in_day].rate;
        temp_per         = _StRateVolData[in_index][in_day].width_per;
    } else {
        base_time        = Time[0];
        offset_baseindex = (int)G_BaseBarDiff * Period() * 60;
        temp_rate        = _StRateVolAllData[in_index].rate;
        temp_per         = _StRateVolAllData[in_index].width_per;
    }

    int temp_width = GetDispMaxWidth( );
    if ( in_day == E_DAYALL ) {
        int all_width = int(ChartGetInteger( 0,CHART_WIDTH_IN_BARS,0 ) - ChartGetInteger( 0,CHART_FIRST_VISIBLE_BAR,0 )) - 10;
        if ( temp_width > all_width ) {
            temp_width = all_width;
        }

    }
    disp_volume    = temp_per * temp_width;

    offsetindex    = (int)(disp_volume * Period() * 60 / 100);
    if ( offsetindex <= Period() * 60 && temp_per > 0) {
        offsetindex = Period() * 60;
    }


    if ( in_day == E_DAYALL ) {
        offsetindex *= -1;
    }

    if ( temp_per >= 50 ) {
        set_color = SetOverColor;
        if ( temp_per >= 80 ) {
            set_color = SetOver2Color;
        }
    }


    ObjectDelete(obj_name);
    ObjectCreate(    obj_name, OBJ_TREND , 0
                    , base_time + offset_baseindex                      , temp_rate
                    , base_time + offset_baseindex + offsetindex        , temp_rate
                    );


    ObjectSet(        obj_name,OBJPROP_COLOR, set_color);
    ObjectSet(        obj_name,OBJPROP_STYLE, STYLE_SOLID);
    ObjectSet(        obj_name,OBJPROP_WIDTH, 1);
    ObjectSet(        obj_name,OBJPROP_BACK , true);
    ObjectSetInteger(0,obj_name,OBJPROP_SELECTABLE, false);     // オブジェクトの選択可否設定
    ObjectSetInteger(0,obj_name,OBJPROP_SELECTED  , false);     // オブジェクトの選択状態
    ObjectSetInteger(0,obj_name,OBJPROP_HIDDEN    , false);     // オブジェクトリスト表示設定
    ObjectSet(        obj_name, OBJPROP_RAY       , false);
}

//+------------------------------------------------------------------+
//| DispDailyLine
//+------------------------------------------------------------------+
void DispDailyLine( e_days in_day , int start_index ) {

    if ( in_day >= E_DAYALL ) {
        return;
    }

    if ( _GBool_DispDailyRateVolume == false ) {
        if ( in_day < E_DAYALL ) {
            return;
        }
    }

    string      obj_name    = StringFormat( "%s_DAYLINE_%d" , OBJ_HEAD , in_day);
    datetime    base_time   = Time[start_index];
    color       temp_color  = clrGray;
    int         temp_solid  = STYLE_DOT;
    if ( TimeDayOfWeek( base_time ) == MONDAY ) {
        temp_color    = SetTextColor;
        temp_solid    = STYLE_SOLID;
    }

    ObjectDelete(    obj_name);
    ObjectCreate(    obj_name, OBJ_VLINE , 0
                    , base_time          , 0
                    );

    ObjectSet(        obj_name,OBJPROP_COLOR, temp_color);
    ObjectSet(        obj_name,OBJPROP_STYLE, temp_solid);
    ObjectSet(        obj_name,OBJPROP_WIDTH, 1);
    ObjectSet(        obj_name,OBJPROP_BACK , true);
    ObjectSetInteger(0,obj_name,OBJPROP_SELECTABLE, false);     // オブジェクトの選択可否設定
    ObjectSetInteger(0,obj_name,OBJPROP_SELECTED  , false);     // オブジェクトの選択状態
    ObjectSetInteger(0,obj_name,OBJPROP_HIDDEN    , false);     // オブジェクトリスト表示設定
    ObjectSet(        obj_name, OBJPROP_RAY       , false);

    if ( in_day == E_DAY0 ) {
        obj_name = StringFormat( "%s_DAYLINE_%d_Add" , OBJ_HEAD , in_day);

        ObjectDelete(    obj_name);
        ObjectCreate(    obj_name, OBJ_VLINE          , 0
                        , base_time    + ONE_DAY_TIME , 0
                        );

        ObjectSet(        obj_name,OBJPROP_COLOR, temp_color);
        ObjectSet(        obj_name,OBJPROP_STYLE, STYLE_DOT);
        ObjectSet(        obj_name,OBJPROP_WIDTH, 1);
        ObjectSet(        obj_name,OBJPROP_BACK , true);
        ObjectSetInteger(0,obj_name,OBJPROP_SELECTABLE, false);     // オブジェクトの選択可否設定
        ObjectSetInteger(0,obj_name,OBJPROP_SELECTED  , false);     // オブジェクトの選択状態
        ObjectSetInteger(0,obj_name,OBJPROP_HIDDEN    , false);     // オブジェクトリスト表示設定
        ObjectSet(        obj_name, OBJPROP_RAY       , false);

    }

}
