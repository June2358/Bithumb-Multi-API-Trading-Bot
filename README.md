# Bithumb Multi-API Trading Bot (빗썸 다중 API 자동매매)

![Python](https://img.shields.io/badge/Python-3.8%2B-blue) ![License](https://img.shields.io/badge/License-MIT-green)

빗썸(Bithumb) API를 활용하여 다수의 API Key를 동시에 운용할 수 있는 파이썬 프로젝트입니다.
`threading` 모듈을 사용하여 각 API Key 별로 독립적인 프로세스를 생성하며, 병렬 처리를 통해 다중 API 요청을 효율적으로 수행합니다.

> **⚠️ 주의 (Disclaimer)**
>
> * **이용 약관 준수**: 본 프로그램은 사용자가 보유한 API Key를 기술적으로 활용하는 도구일 뿐입니다. 거래소의 이용 약관 및 API 사용 정책을 반드시 준수해야 합니다.
> * **책임 고지**: 본 코드는 API 연동 및 병렬 처리 구조를 예시하기 위한 목적으로 작성되었습니다. 실제 사용으로 인해 발생하는 모든 결과에 대한 책임은 사용자 본인에게 있습니다.

## 🛠 주요 기능 (Features)

* **Multi-Threading Support**: Python의 `threading`을 활용하여 여러 개의 API Key를 동시에 제어합니다.
* **Interval Management**: 
    * API 호출 간격을 설정된 범위 내에서 처리합니다.
    * 각 스레드는 독립적인 대기 시간을 가집니다.
* **Secure Key Management**: API 키와 시크릿 키를 별도의 JSON 파일로 분리하여 관리합니다.
* **Log System**: 각 API Key(스레드)별 동작 상태를 실시간으로 출력합니다.

## 📂 파일 구조 (File Structure)

```bash
├── coin.py                 # 메인 실행 파일
├── api_keys.json           # [비공개] API 키 저장소
├── api_keys.sample.json    # API 키 설정 예시
├── .gitignore              # 보안 설정
└── README.md               # 프로젝트 설명서
```

## 🚀 설치 및 설정 (Installation)

### 1. 라이브러리 설치
이 프로젝트는 `pybithumb` 라이브러리를 사용합니다.

```bash
pip install pybithumb
```

### 2. API 키 설정
`api_keys.sample.json` 파일을 복사하여 `api_keys.json`을 생성하고, 사용할 API 키 정보를 입력합니다.

```json
[
    {
        "name": "API_Key_1",
        "connect_key": "YOUR_CONNECT_KEY",
        "secret_key": "YOUR_SECRET_KEY"
    },
    {
        "name": "API_Key_2",
        "connect_key": "YOUR_CONNECT_KEY",
        "secret_key": "YOUR_SECRET_KEY"
    }
]
```

## ⚙️ 설정 변경 (Configuration)
`coin.py` 상단의 상수를 수정하여 파라미터를 조정할 수 있습니다.

```python
# 매수 금액 설정 (KRW)
MIN_BUY_KRW = 5000
MAX_BUY_KRW = 20000

# 대기 시간 설정 (초 단위)
MIN_WAIT_SEC = 1800
MAX_WAIT_SEC = 7200
```

## 💻 사용 방법 (Usage)
터미널에서 아래 명령어로 실행합니다.

```bash
python coin.py
```

실행 시 등록된 API Key 개수만큼 스레드가 시작됩니다.

```plaintext
=== 빗썸 자동매매 봇 시작 (2개 API Key) ===
대상 코인: KRW-BTC
...
[2024-XX-XX 12:00:00] [API_Key_1] 프로세스 시작
[2024-XX-XX 12:00:05] [API_Key_2] 프로세스 시작
...
```
