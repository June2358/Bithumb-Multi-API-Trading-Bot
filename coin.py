import pybithumb
import time
import json
import threading
import datetime
import random
import traceback

# 설정 변수
TARGET_COIN = "ETH"        # 거래할 코인
MIN_BUY_KRW = 10000        # 최소 매수 금액 (원)
MAX_BUY_KRW = 20000        # 최대 매수 금액 (원)

# 대기 시간 설정 (초 단위)
MIN_WAIT_SEC = 1800        # 30분
MAX_WAIT_SEC = 7200        # 2시간

def log(name, msg):
    """로그 출력 함수"""
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{now}] [{name}] {msg}")

def load_api_keys(filename="api_keys.json"):
    """JSON 파일에서 API 키 로드"""
    try:
        with open(filename, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"Error: {filename} 파일을 읽을 수 없습니다. - {e}")
        return []

def bot_loop(api_key_config):
    """API Key별 메인 루프"""
    name = api_key_config["name"]
    connect_key = api_key_config["connect_key"]
    secret_key = api_key_config["secret_key"]
    bithumb = pybithumb.Bithumb(connect_key, secret_key)
    coin = TARGET_COIN

    log(name, "프로세스 시작")

    while True:
        try:
            # 1. 매수 금액 설정
            random_buy_krw = random.randint(MIN_BUY_KRW, MAX_BUY_KRW)
            random_buy_krw = int(random_buy_krw / 100) * 100  # 100원 단위 절삭

            log(name, f"--- 사이클 시작 (목표 매수금액: {random_buy_krw:,}원) ---")

            # 2. 매수 로직
            # 잔액 조회
            balance = bithumb.get_balance(coin)
            available_krw = balance[2]

            if available_krw < random_buy_krw:
                log(name, f"잔액 부족으로 대기 (보유: {available_krw:,.0f}원)")
                time.sleep(300)
                continue

            # 현재가 조회 및 매수 수량 계산
            current_price = pybithumb.get_current_price(coin)
            buy_quantity = random_buy_krw / current_price
            buy_quantity = round(buy_quantity, 8)

            # 매수 주문 (시장가)
            log(name, f"매수 시도: {buy_quantity} {coin} (약 {random_buy_krw:,}원)")
            buy_order = bithumb.buy_market_order(coin, buy_quantity)
            log(name, f"매수 주문 결과: {buy_order}")

            # 3. 매수 후 대기
            wait_time = random.uniform(MIN_WAIT_SEC, MAX_WAIT_SEC)
            log(name, f"매수 완료. {wait_time/60:.1f}분 동안 보유합니다...")
            time.sleep(wait_time)

            # 4. 매도 로직
            # 잔액 재조회
            balance = bithumb.get_balance(coin)
            available_coin = balance[0]

            # 전량 매도 (시장가)
            if available_coin > 0.0001:
                log(name, f"전량 매도 시도: {available_coin} {coin}")
                sell_order = bithumb.sell_market_order(coin, available_coin)
                log(name, f"매도 주문 결과: {sell_order}")
            else:
                log(name, "매도할 코인이 없습니다.")

            # 5. 매도 후 휴식
            wait_time = random.uniform(MIN_WAIT_SEC, MAX_WAIT_SEC)
            log(name, f"매도 완료. {wait_time/60:.1f}분 휴식 후 재개합니다.\n")
            time.sleep(wait_time)

        except Exception as e:
            log(name, f"에러 발생: {e}")
            log(name, traceback.format_exc())
            time.sleep(60)

if __name__ == "__main__":
    # API 키 로드
    api_keys = load_api_keys()

    if not api_keys:
        print("API 키가 없습니다. api_keys.json을 확인하세요.")
        exit()

    # 봇 실행
    print(f"=== 자동매매 시작 (총 {len(api_keys)}개 API Key) ===")
    
    threads = []
    for api_key_config in api_keys:
        t = threading.Thread(target=bot_loop, args=(api_key_config,))
        t.daemon = True
        t.start()
        threads.append(t)
        time.sleep(random.uniform(5, 20))

    # 메인 스레드 유지
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("프로그램을 종료합니다.")