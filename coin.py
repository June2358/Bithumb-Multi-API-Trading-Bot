import pybithumb
import time
import json
import math
import threading
import logging
import random
import sys

# 설정 변수
TARGET_COIN = "ETH"        # 거래할 코인
MIN_BUY_KRW = 10000        # 최소 매수 금액 (원)
MAX_BUY_KRW = 20000        # 최대 매수 금액 (원)

# 대기 시간 설정 (초 단위)
MIN_WAIT_SEC = 1800        # 30분
MAX_WAIT_SEC = 7200        # 2시간

def load_api_keys(filename="api_keys.json"):
    """JSON 파일에서 API 키 로드"""
    try:
        with open(filename, "r", encoding="utf-8") as f:
            api_keys = json.load(f)
        if not isinstance(api_keys, list) or any(
            not isinstance(config, dict) or any(
                not isinstance(config.get(key), str) or not config[key].strip()
                for key in ("name", "connect_key", "secret_key")
            )
            for config in api_keys
        ):
            raise ValueError("각 항목에 name, connect_key, secret_key 문자열이 필요합니다.")
        return api_keys
    except (OSError, ValueError) as e:
        print(f"오류: {filename} 파일을 읽을 수 없습니다. - {e}")
        return []

def bot_loop(api_key_config):
    """API Key별 메인 루프"""
    logger = logging.getLogger(api_key_config["name"])
    connect_key = api_key_config["connect_key"]
    secret_key = api_key_config["secret_key"]
    bithumb = pybithumb.Bithumb(connect_key, secret_key)
    coin = TARGET_COIN

    logger.info("프로세스 시작")

    while True:
        try:
            # 1. 매수 금액 설정
            random_buy_krw = random.randint(MIN_BUY_KRW, MAX_BUY_KRW)
            random_buy_krw = random_buy_krw // 100 * 100  # 100원 단위 절삭

            logger.info(f"--- 사이클 시작 (목표 매수금액: {random_buy_krw:,}원) ---")

            # 2. 매수 로직
            # 잔액 조회
            balance = bithumb.get_balance(coin)
            available_krw = balance[2] - balance[3]
            if not math.isfinite(available_krw) or available_krw < 0:
                raise ValueError("사용 가능한 원화 잔액을 확인할 수 없습니다.")

            if available_krw < random_buy_krw:
                logger.info(f"잔액 부족으로 대기 (보유: {available_krw:,.0f}원)")
                time.sleep(300)
                continue

            # 현재가 조회 및 매수 수량 계산
            current_price = pybithumb.get_current_price(coin)
            if not isinstance(current_price, (int, float)) or not math.isfinite(current_price) or current_price <= 0:
                raise ValueError("정상적인 현재가를 조회하지 못했습니다.")
            buy_quantity = random_buy_krw / current_price
            buy_quantity = round(buy_quantity, 8)

            # 매수 주문 (시장가)
            logger.info(f"매수 시도: {buy_quantity} {coin} (약 {random_buy_krw:,}원)")
            buy_order = bithumb.buy_market_order(coin, buy_quantity)
            logger.info(f"매수 주문 결과: {buy_order}")
            if not isinstance(buy_order, tuple) or len(buy_order) != 4 or not buy_order[2]:
                raise ValueError("매수 주문 접수를 확인하지 못해 이번 사이클을 중단합니다.")

            # 3. 매수 후 대기
            wait_time = random.uniform(MIN_WAIT_SEC, MAX_WAIT_SEC)
            logger.info(f"매수 주문 접수. {wait_time/60:.1f}분 후 잔액을 확인합니다...")
            time.sleep(wait_time)

            # 4. 매도 로직
            # 잔액 재조회
            balance = bithumb.get_balance(coin)
            available_coin = balance[0] - balance[1]
            if not math.isfinite(available_coin) or available_coin < 0:
                raise ValueError("사용 가능한 코인 잔액을 확인할 수 없습니다.")

            # 전량 매도 (시장가)
            if available_coin > 0.0001:
                logger.info(f"전량 매도 시도: {available_coin} {coin}")
                sell_order = bithumb.sell_market_order(coin, available_coin)
                logger.info(f"매도 주문 결과: {sell_order}")
                if not isinstance(sell_order, tuple) or len(sell_order) != 4 or not sell_order[2]:
                    raise ValueError("매도 주문 접수를 확인하지 못했습니다.")
            else:
                logger.info("매도할 코인이 없습니다.")

            # 5. 매도 후 휴식
            wait_time = random.uniform(MIN_WAIT_SEC, MAX_WAIT_SEC)
            logger.info(f"{wait_time/60:.1f}분 휴식 후 재개합니다.\n")
            time.sleep(wait_time)

        except Exception as e:
            logger.exception("에러 발생: %s", e)
            time.sleep(60)

if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="[%(asctime)s] [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        stream=sys.stdout,
    )
    if not (
        all(isinstance(seconds, (int, float)) and math.isfinite(seconds)
            for seconds in (MIN_WAIT_SEC, MAX_WAIT_SEC))
        and 0 <= MIN_WAIT_SEC <= MAX_WAIT_SEC <= threading.TIMEOUT_MAX
    ):
        raise SystemExit(f"대기 시간은 0 이상, {threading.TIMEOUT_MAX:g}초 이하인 숫자이며 최솟값이 최댓값 이하여야 합니다.")

    # API 키 로드
    api_keys = load_api_keys()

    if not api_keys:
        print("API 키가 없습니다. api_keys.json을 확인하세요.")
        raise SystemExit(1)

    # 봇 실행
    print(f"=== 자동매매 시작 (총 {len(api_keys)}개 API Key) ===")
    
    for api_key_config in api_keys:
        t = threading.Thread(target=bot_loop, args=(api_key_config,), daemon=True)
        t.start()
        time.sleep(random.uniform(5, 20))

    # 메인 스레드 유지
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("프로그램을 종료합니다.")
