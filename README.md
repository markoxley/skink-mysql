# skink-mysql

Pure-Skink MySQL/MariaDB driver — wire protocol, authentication, and
`dbx` adapter. No native client library required.

## Features

- Protocol-41 handshake and capability negotiation
- `mysql_native_password` and `caching_sha2_password` authentication
  - `caching_sha2` fast auth and full auth (RSA-OAEP key exchange when
    not on TLS, cleartext-password over TLS when it is)
  - Auth-switch requests (`0xfe`) are handled mid-handshake
- `COM_QUERY` (text protocol) and prepared statements
  (`COM_STMT_PREPARE` / `EXECUTE` / `CLOSE`, binary row protocol)
- `?` placeholders bound server-side — no client-side rewriting
- Optional TLS upgrade (`?tls=true` / `?ssl=required`)
- Transactions (`BEGIN` / `COMMIT` / `ROLLBACK`), `COM_PING`
- `dbx` driver registered under `mysql://` and `mariadb://`

## Install

```bash
scales add markoxley/skink-mysql
```

## Usage

```skink
import "mod/markoxley/skink-mysql"
import "mod/markoxley/skink-dbx/dbx_value"

fn main() {
    // Direct API
    c, err := mysql.Dial("mysql://user:pass@127.0.0.1:3306/mydb")
    ...
    res, _ := mysql.Query(&c, "SELECT id, name FROM users")

    // Bound parameters via prepared statements
    res2, _ := mysql.QueryParams(&c,
        "SELECT * FROM users WHERE id = ? AND active = ?",
        []dbx_value.Value{dbx_value.Int(int64(7)), dbx_value.Bool(true)})

    // Or through the generic dbx registry
    mysql.Register()
    conn, _ := dbx.Open("mysql://user:pass@host/mydb")
    rows, _ := conn.Query("SELECT ... WHERE a = ?", args)
    tx, _ := conn.Begin()
    tx.Exec("UPDATE ...", args)
    tx.Commit()
}
```

## DSN

```
mysql://[user[:password]@]host[:port][/database][?tls=true|required]
mariadb://...                      (alias)
```

Query parameters:
- `tls=true` / `ssl=true` — opportunistic TLS (upgrades if the server
  advertises `CLIENT_SSL`)
- `tls=required` — same, but intended to fail closed if TLS can't be
  negotiated

## Type mapping

| MySQL column                         | `dbx_value` kind |
|--------------------------------------|------------------|
| TINY/SHORT/LONG/LONGLONG/INT24/YEAR  | `KIND_INT`       |
| FLOAT/DOUBLE                         | `KIND_FLOAT`     |
| DATE/DATETIME/TIMESTAMP              | `KIND_TIME` (Unix µs) |
| TIME                                 | `KIND_TEXT`      |
| DECIMAL/NEWDECIMAL/JSON/ENUM/SET     | `KIND_TEXT`      |
| BLOB family with `binary` flag       | `KIND_BLOB`      |
| everything else                      | `KIND_TEXT`      |
| NULL                                 | `KIND_NULL`      |

`KIND_TIME` parameters bind as `'YYYY-MM-DD HH:MM:SS.ffffff'` and the
server coerces to the column type.

## Limitations

- Single result set per query — `CLIENT_MULTI_RESULTS` is negotiated but
  stored procedures returning multiple sets should be consumed one
  query at a time.
- `LOAD DATA LOCAL INFILE` requests are refused.
- `CLIENT_DEPRECATE_EOF` is not set, so result-set terminators arrive as
  EOF packets (this is what the driver parses).
- MariaDB `ed25519` auth is not supported; use
  `mysql_native_password` accounts for MariaDB.

## Development

```bash
./run_tests.sh        # unit + fake-server suites
./test_live.sh        # podman mysql:8.0 live test (skips without podman)
./install_local.sh    # verify scales-installability via local mirror
```

Test layout: `pkt_test` (framing/lenenc), `type_test` (decode/encode),
`conn_test` (fake-server handshake/query/prepare/errors/tx/ping),
`dbx_test` (registry + adapter), `live_test` (real server, env-gated on
`SKINK_MYSQL_DSN`).
