# 그린(8.4) 인스턴스 접속 안내 — 백엔드 검증용

| | |
|---|---|
| **목적** | RDS MySQL 8.4 전환 전, 실제 8.4 서버에서 쿼리 검증 (요청서 Q2 회신) |
| **엔진** | MySQL **8.4.11** |
| **성격** | 운영 DB의 **읽기 전용 복제본**. 데이터는 운영과 동일하며 실시간 동기화된다 |
| **유효 기간** | 스위치오버까지. 전환되면 이 엔드포인트는 사라진다 |

---

## 접속 경로

RDS 보안그룹에 CIDR 인그레스가 없어 **VPN 만으로는 3306 이 닿지 않는다.**
모니터링 노드를 경유하는 SSH 터널이 필요하다 (blue 접속과 동일한 경로).

```bash
# 1) VPN 연결 후, 터널 개설
ssh -f -N -L 13306:groble-prod-mysql-green-ftzmon.cloukwy4oscs.ap-northeast-2.rds.amazonaws.com:3306 \
    -i <groble_prod_ec2_key_pair>.pem ubuntu@10.0.1.193

# 2) 접속
mysql -h 127.0.0.1 -P 13306 -u groble_root -p
```

- **계정/비밀번호는 운영과 동일하다** (복제본이므로 계정까지 승계된다)
- 데이터베이스: `groble_prod_database`

---

## ⚠️ MySQL 9.x 클라이언트로는 접속되지 않는다

`groble_root` 는 `mysql_native_password` 를 쓰는데, **MySQL 9.x 클라이언트는 이 플러그인을
제거해서** 아래 오류로 실패한다.

```
ERROR 2059 (HY000): Authentication plugin 'mysql_native_password' cannot be loaded
```

**8.x 클라이언트나 `pymysql` 을 쓸 것.** (`mysql --version` 으로 확인)

> RDS 8.4 는 AWS 가 `mysql_native_password = ON` 으로 고정해 두어 **서버 쪽은 문제가 없다.**
> 클라이언트 쪽 제약일 뿐이다.

---

## 확인해 주시면 좋을 것

회신에서 말씀하신 대로 **어드민 통계 쿼리 위주**로 부탁드립니다.

1. **문법** — `JdbcTemplate` / `createNativeQuery` 로 작성한 SQL 이 8.4 에서 그대로 도는가
2. **성능** — 옵티마이저 변화로 실행계획이 나빠진 쿼리가 있는가 (`EXPLAIN` 비교)

> **쓰기는 하지 말아 주세요.** 그린은 읽기 전용이며, 쓰기가 들어가면 운영과 어긋납니다.

문제가 발견되면 **전환 전이므로 그린만 삭제하면 됩니다** — 운영에는 아무 영향이 없습니다.
