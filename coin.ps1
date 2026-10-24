function Invoke-BithumbMain {
    param(
        [string]$ScriptPath,
        $Settings = [pscustomobject]@{
            Market = 'KRW-ETH'
            MinBuyKrw = 10000
            MaxBuyKrw = 20000
            MinWaitSec = 1800
            MaxWaitSec = 7200
            InsufficientWaitSec = 300
            ReadErrorWaitSec = 60
            MinStaggerSec = 5
            MaxStaggerSec = 20
            SellThreshold = [decimal]0.0001
        }
    )

    $ErrorActionPreference = 'Stop'
    Test-BithumbSettings -Settings $Settings
    $ScriptPath = [IO.Path]::GetFullPath($ScriptPath)
    $accounts = @(Read-BithumbAccounts -Path (Join-Path (Split-Path -Parent $ScriptPath) 'api_keys.json'))
    $asset = $Settings.Market.Substring(4)
    Write-Host "실제 원화로 $asset 매수 후 기존 보유분을 포함한 사용 가능 $asset 전량을 매도합니다."
    if ((Read-Host '계속하려면 대문자 Y를 입력하세요') -cne 'Y') {
        Write-Host '자동매매를 취소했습니다.'
        return 0
    }

    $jobs = @()
    $reported = @{}
    try {
        for ($index = 0; $index -lt $accounts.Count; $index++) {
            $jobs += Start-Job -Name $accounts[$index].name -ArgumentList $ScriptPath, $accounts[$index], $Settings -ScriptBlock {
                param($CorePath, $Account, $WorkerSettings)
                . $CorePath
                Invoke-BithumbAccount -Account $Account -Settings $WorkerSettings
            }
            if ($index -lt $accounts.Count - 1) {
                Start-Sleep -Seconds (Get-Random -Minimum $Settings.MinStaggerSec -Maximum ($Settings.MaxStaggerSec + 1))
            }
        }
        while ($true) {
            foreach ($job in $jobs) {
                Receive-Job -Job $job -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
                if ($job.State -in @('Failed', 'Stopped', 'Completed') -and -not $reported.ContainsKey($job.Id)) {
                    $reason = $job.ChildJobs[0].JobStateInfo.Reason
                    $message = if ($null -ne $reason) { $reason.Message } else { '계정 작업이 종료되었습니다. 주문 내역을 확인하세요.' }
                    Write-Host (Write-BithumbLog -AccountName $job.Name -Message $message)
                    $reported[$job.Id] = $true
                }
            }
            if (@($jobs | Where-Object { $_.State -notin @('Failed', 'Stopped', 'Completed') }).Count -eq 0) {
                Write-Host '실행 중인 계정이 없어 종료합니다.'
                return 1
            }
            Start-Sleep -Seconds 1
        }
    }
    finally {
        if ($jobs.Count -gt 0) {
            $jobs | Where-Object { $_.State -notin @('Failed', 'Stopped', 'Completed') } | Stop-Job -ErrorAction SilentlyContinue
            $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-BithumbAccounts {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) {
        throw 'api_keys.json 파일이 없습니다. api_keys.sample.json을 api_keys.json으로 복사한 뒤 빗썸 API 2.0의 access_key, secret_key와 계정 이름을 입력하고, API 설정에서 이 PC의 접속 IP를 허용하세요.'
    }
    try {
        $json = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
        if (-not $json.TrimStart().StartsWith('[')) { throw '배열 형식이 아닙니다.' }
        ConvertFrom-Json -InputObject $json -ErrorAction Stop | Out-Null
        # PowerShell 5.1의 최상위 배열 열거와 중첩 배열 손실을 피합니다.
        $accounts = (ConvertFrom-Json -InputObject ('{"accounts":' + $json + '}') -ErrorAction Stop).accounts
        if ($accounts -isnot [array] -or $accounts.Count -eq 0) { throw '계정이 없습니다.' }
        $keys = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($account in $accounts) {
            if ($null -eq $account -or $account -isnot [pscustomobject]) { throw '계정 항목이 잘못되었습니다.' }
            foreach ($field in @('name', 'access_key', 'secret_key')) {
                if ($account.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($account.$field)) {
                    throw '필수 문자열이 없습니다.'
                }
            }
            if (-not $keys.Add($account.access_key)) { throw '중복된 access_key가 있습니다.' }
        }
        return $accounts
    }
    catch {
        throw 'api_keys.json은 name, access_key, secret_key 문자열이 있는 비어 있지 않은 배열이어야 하며 access_key가 중복되면 안 됩니다.'
    }
}

function Test-BithumbSettings {
    param($Settings)
    if ($Settings.Market -isnot [string] -or $Settings.Market -cnotmatch '^KRW-[A-Z0-9]+$') { throw '거래 시장은 KRW-ETH와 같은 원화 시장 이름이어야 합니다.' }
    foreach ($field in @('MinBuyKrw', 'MaxBuyKrw', 'MinWaitSec', 'MaxWaitSec', 'InsufficientWaitSec', 'ReadErrorWaitSec', 'MinStaggerSec', 'MaxStaggerSec')) {
        $value = $Settings.$field
        if ($null -eq $value -or $value -is [string] -or $value -is [bool] -or
            $value -lt 0 -or $value -gt ([int]::MaxValue - 1) -or [double]::IsNaN([double]$value) -or
            [math]::Floor([double]$value) -ne $value) { throw '금액과 대기 시간 설정은 범위 안의 음수가 아닌 정수여야 합니다.' }
    }
    if ($Settings.MinBuyKrw -lt 100 -or $Settings.MinBuyKrw -gt $Settings.MaxBuyKrw -or
        $Settings.MinWaitSec -gt $Settings.MaxWaitSec -or $Settings.MinStaggerSec -gt $Settings.MaxStaggerSec) {
        throw '최소 매수 금액은 100원 이상이며 각 최솟값은 최댓값 이하여야 합니다.'
    }
    $null = ConvertTo-BithumbDecimal -Value $Settings.SellThreshold
}

function Write-BithumbLog {
    param([string]$AccountName, [string]$Message)
    Write-Output "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$AccountName] $Message"
}

function ConvertTo-BithumbDecimal {
    param($Value)
    $number = [decimal]0
    if ($null -eq $Value -or $Value -is [bool] -or
        -not [decimal]::TryParse([Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture),
            [Globalization.NumberStyles]::AllowDecimalPoint, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or $number -lt 0) {
        throw 'API 응답의 금액 또는 수량을 확인할 수 없습니다.'
    }
    return $number
}

function New-BithumbToken {
    param($Account, [string]$Query = '')
    $payload = [ordered]@{
        access_key = $Account.access_key
        nonce = [guid]::NewGuid().ToString()
        timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    }
    if ($Query.Length -gt 0) {
        $sha = [Security.Cryptography.SHA512]::Create()
        try {
            $payload.query_hash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Query))).Replace('-', '').ToLowerInvariant()
            $payload.query_hash_alg = 'SHA512'
        }
        finally { $sha.Dispose() }
    }
    $parts = foreach ($value in @([ordered]@{ alg = 'HS256'; typ = 'JWT' }, $payload)) {
        $json = ConvertTo-Json -InputObject $value -Compress
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }
    $inputText = $parts -join '.'
    $hmac = New-Object Security.Cryptography.HMACSHA256
    try {
        $hmac.Key = [Text.Encoding]::UTF8.GetBytes($Account.secret_key)
        $signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($inputText))).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        return "$inputText.$signature"
    }
    finally { $hmac.Dispose() }
}

function Invoke-BithumbRequest {
    param($Account, [string]$Method, [string]$Path, [System.Collections.IDictionary]$Parameters)
    if (-not (($Method -ceq 'GET' -and $Path -ceq '/v1/orders/chance') -or
        ($Method -ceq 'POST' -and $Path -ceq '/v2/orders'))) { throw '지원하지 않는 API 요청입니다.' }
    $query = (@(foreach ($key in $Parameters.Keys) {
        [uri]::EscapeDataString([string]$key) + '=' + [uri]::EscapeDataString([Convert]::ToString($Parameters[$key], [Globalization.CultureInfo]::InvariantCulture))
    })) -join '&'
    $arguments = @{
        Uri = 'https://api.bithumb.com' + $Path
        Method = $Method
        Headers = @{ Authorization = 'Bearer ' + (New-BithumbToken -Account $Account -Query $query) }
        TimeoutSec = 15
        MaximumRedirection = 0
        ErrorAction = 'Stop'
    }
    if ($Method -ceq 'GET') {
        if ($query) { $arguments.Uri += '?' + $query }
    }
    else {
        $arguments.ContentType = 'application/json; charset=utf-8'
        $arguments.Body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Parameters -Compress))
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try { return Invoke-RestMethod @arguments }
    catch {
        $status = if ($null -ne $_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { '연결 또는 시간 초과' }
        throw "API 요청 실패: $Method $Path ($status)."
    }
}

function Invoke-BithumbAccount {
    param($Account, $Settings)
    $ErrorActionPreference = 'Stop'
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $label = $Account.name
    $asset = $Settings.Market.Substring(4)
    Write-BithumbLog -AccountName $label -Message '계정 작업을 시작합니다.'
    while ($true) {
        $buyKrw = [decimal]([math]::Floor((Get-Random -Minimum $Settings.MinBuyKrw -Maximum ($Settings.MaxBuyKrw + 1)) / 100) * 100)
        try {
            $chance = Invoke-BithumbRequest -Account $Account -Method GET -Path '/v1/orders/chance' -Parameters ([ordered]@{ market = $Settings.Market })
            if ($chance.market.id -cne $Settings.Market -or $chance.market.state -cne 'active' -or
                $chance.bid_account.currency -cne 'KRW' -or $chance.ask_account.currency -cne $asset -or
                $chance.market.order_sides -cnotcontains 'bid' -or $chance.market.order_sides -cnotcontains 'ask' -or
                $chance.market.bid_types -cnotcontains 'price' -or $chance.market.ask_types -cnotcontains 'market') {
                throw "거래 가능한 $asset 시장 정보를 확인할 수 없습니다."
            }
            $availableKrw = ConvertTo-BithumbDecimal -Value $chance.bid_account.balance
            $fee = ConvertTo-BithumbDecimal -Value $chance.bid_fee
            $minimum = ConvertTo-BithumbDecimal -Value $chance.market.bid.min_total
            if ($minimum -le 0 -or $fee -ge 1) { throw '최소 주문 금액 또는 수수료율을 확인할 수 없습니다.' }
        }
        catch {
            Write-BithumbLog -AccountName $label -Message "매수 전 조회 실패: $($_.Exception.Message) $($Settings.ReadErrorWaitSec)초 후 다시 조회합니다."
            Start-Sleep -Seconds $Settings.ReadErrorWaitSec
            continue
        }
        if ($buyKrw -lt $minimum) { throw "[$label] 설정된 매수 금액이 시장 최소 주문 금액보다 작아 계정을 중단합니다." }
        if ($availableKrw -lt $buyKrw * (1 + $fee)) {
            Write-BithumbLog -AccountName $label -Message "수수료를 포함한 원화 잔액이 부족하여 $($Settings.InsufficientWaitSec)초 대기합니다."
            Start-Sleep -Seconds $Settings.InsufficientWaitSec
            continue
        }

        $clientOrderId = [guid]::NewGuid().ToString()
        try {
            Write-BithumbLog -AccountName $label -Message "매수 요청: $($buyKrw.ToString($culture))원, client_order_id=$clientOrderId"
            $buy = Invoke-BithumbRequest -Account $Account -Method POST -Path '/v2/orders' -Parameters ([ordered]@{
                market = $Settings.Market
                side = 'bid'
                order_type = 'price'
                price = $buyKrw.ToString($culture)
                client_order_id = $clientOrderId
            })
            if ($buy.order_id -isnot [string] -or [string]::IsNullOrWhiteSpace($buy.order_id)) { throw '매수 주문 접수를 확인하지 못했습니다.' }
            $wait = Get-Random -Minimum $Settings.MinWaitSec -Maximum ($Settings.MaxWaitSec + 1)
            Write-BithumbLog -AccountName $label -Message "매수 주문 접수. $wait 초 후 사용 가능 $asset 수량을 확인합니다."
            Start-Sleep -Seconds $wait
            $chance = Invoke-BithumbRequest -Account $Account -Method GET -Path '/v1/orders/chance' -Parameters ([ordered]@{ market = $Settings.Market })
            if ($chance.market.id -cne $Settings.Market -or $chance.market.state -cne 'active' -or
                $chance.ask_account.currency -cne $asset -or $chance.market.order_sides -cnotcontains 'ask' -or
                $chance.market.ask_types -cnotcontains 'market') { throw "매도 가능한 $asset 시장 정보를 확인할 수 없습니다." }
            $availableCoin = ConvertTo-BithumbDecimal -Value $chance.ask_account.balance
            if ($availableCoin -gt $Settings.SellThreshold) {
                $clientOrderId = [guid]::NewGuid().ToString()
                Write-BithumbLog -AccountName $label -Message "사용 가능 $asset 전량 매도 요청: $($availableCoin.ToString($culture)) $asset, client_order_id=$clientOrderId"
                $sell = Invoke-BithumbRequest -Account $Account -Method POST -Path '/v2/orders' -Parameters ([ordered]@{
                    market = $Settings.Market
                    side = 'ask'
                    order_type = 'market'
                    volume = $availableCoin.ToString($culture)
                    client_order_id = $clientOrderId
                })
                if ($sell.order_id -isnot [string] -or [string]::IsNullOrWhiteSpace($sell.order_id)) { throw '매도 주문 접수를 확인하지 못했습니다.' }
                Write-BithumbLog -AccountName $label -Message '매도 주문을 접수했습니다.'
            }
            else { Write-BithumbLog -AccountName $label -Message "매도 기준 수량을 넘는 사용 가능 $asset 수량이 없습니다." }
            $wait = Get-Random -Minimum $Settings.MinWaitSec -Maximum ($Settings.MaxWaitSec + 1)
            Write-BithumbLog -AccountName $label -Message "$wait 초 휴식 후 재개합니다."
            Start-Sleep -Seconds $wait
        }
        catch {
            Write-BithumbLog -AccountName $label -Message "매수 요청 이후 오류: $($_.Exception.Message) 계정을 중단합니다. client_order_id=$clientOrderId. 주문 내역을 직접 확인하세요."
            throw '주문 상태 확인이 필요하여 이 계정의 자동매매를 중단했습니다.'
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { exit (Invoke-BithumbMain -ScriptPath $PSCommandPath) }
    catch {
        Write-Host "오류: $($_.Exception.Message)"
        exit 1
    }
}
