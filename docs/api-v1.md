# SQLiteREST API v1

面向 iOS 应用内 SQLite 数据库的 REST 调试接口，基于统一响应格式（Envelope），使用 `rowid` 作为行唯一标识。

---

## 基础信息

| 项目 | 说明 |
|------|------|
| **Base URL** | `http://{device_ip}:{port}/api/v1` |
| **Content-Type** | 请求/响应均为 `application/json`（除文档另有说明） |
| **字符编码** | UTF-8 |

---

## 统一响应格式 (Envelope)

所有接口均采用同一 JSON 结构，便于前端统一处理成功/失败与加载状态。

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `success` | boolean | 是 | 请求是否成功 |
| `data` | object / array | 成功时 | 业务数据负载 |
| `meta` | object | 可选 | 分页、耗时等元信息 |
| `error` | object | 失败时 | 错误码与调试信息 |

**成功示例：**
```json
{
  "success": true,
  "data": { ... }
}
```

**失败示例：**
```json
{
  "success": false,
  "error": {
    "code": "invalid_table",
    "message": "Table not found: xyz"
  }
}
```

---

## 1. 数据库信息 (DB)

### 1.1 获取数据库信息

获取当前已打开数据库文件的物理信息（用于 Dashboard 等）。

| 项目 | 说明 |
|------|------|
| **Method** | `GET` |
| **Path** | `/api/v1/db/info` |
| **Query** | 无 |

**Response 200 — success**

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.filename` | string | 数据库文件名 |
| `data.path` | string | 完整路径（可脱敏） |
| `data.sizeBytes` | number | 文件大小（字节） |
| `data.journalMode` | string | 可选，如 `"wal"` |
| `data.integrity` | string | 可选，如 `"ok"` |

**示例：**
```json
{
  "success": true,
  "data": {
    "filename": "app_database.sqlite",
    "path": "/var/mobile/Containers/.../Documents/db.sqlite",
    "sizeBytes": 1024000,
    "journalMode": "wal",
    "integrity": "ok"
  }
}
```

---

### 1.2 获取系统与数据库元信息

聚合数据库底层元信息 + 设备系统版本 + App 版本，方便调试时快速核对环境。

| 项目 | 说明 |
|------|------|
| **Method** | `GET` |
| **Path** | `/api/v1/system/info` |
| **Query** | 无 |

**Response 200 — success**

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.database.absolutePath` | string | 数据库绝对路径 |
| `data.database.pageSize` | number | SQLite 页大小 |
| `data.database.pageCount` | number | 总页数 |
| `data.database.freelistCount` | number | 空闲页数 |
| `data.database.encoding` | string | 编码，如 `UTF-8` |
| `data.database.sqliteVersion` | string | SQLite 运行时版本 |
| `data.device.systemName` | string | 系统名，如 `iOS` |
| `data.device.systemVersion` | string | 系统版本 |
| `data.device.model` | string | 设备型号 |
| `data.app.bundleIdentifier` | string | App Bundle ID |
| `data.app.version` | string | App 版本号 |
| `data.app.build` | string | App Build 号 |

**示例：**
```json
{
  "success": true,
  "data": {
    "database": {
      "filename": "Northwind_small.sqlite",
      "absolutePath": "/var/mobile/Containers/Data/Application/.../Northwind_small.sqlite",
      "sizeBytes": 1679360,
      "estimatedSizeBytes": 1679360,
      "pageSize": 4096,
      "pageCount": 410,
      "freelistCount": 1,
      "schemaVersion": 9,
      "userVersion": 0,
      "autoVacuum": 0,
      "synchronous": 2,
      "sqliteVersion": "3.43.2",
      "encoding": "UTF-8",
      "journalMode": "wal",
      "integrity": "ok"
    },
    "device": {
      "name": "iPhone",
      "model": "iPhone",
      "localizedModel": "iPhone",
      "systemName": "iOS",
      "systemVersion": "18.2",
      "identifierForVendor": "A1B2C3D4-E5F6-...."
    },
    "app": {
      "bundleIdentifier": "com.example.SQLiteREST",
      "version": "1.0",
      "build": "1"
    }
  }
}
```

---

### 1.3 执行原始 SQL

执行任意 SQL（查询或执行类），参数化绑定以防注入。

| 项目 | 说明 |
|------|------|
| **Method** | `POST` |
| **Path** | `/api/v1/db/sql` |
| **Body** | JSON 见下 |

**Request Body**

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sql` | string | 是 | SQL 语句，占位符为 `?` |
| `params` | array | 否 | 与 `?` 顺序对应的参数列表 |

**示例：**
```json
{
  "sql": "SELECT * FROM users WHERE age > ? LIMIT 10",
  "params": [20]
}
```

**Response 200 — 查询类 (SELECT / WITH)**

| 字段 | 类型 | 说明 |
|------|------|------|
| `meta.executionTime` | number | 可选，执行耗时（秒） |
| `data.type` | string | 固定 `"query"` |
| `data.columns` | string[] | 列名 |
| `data.rows` | array[] | 行数据，每行为值数组（与 columns 顺序一致） |

**示例：**
```json
{
  "success": true,
  "meta": { "executionTime": 0.012 },
  "data": {
    "type": "query",
    "columns": ["id", "name", "age"],
    "rows": [
      [1, "Alice", 25],
      [2, "Bob", 30]
    ]
  }
}
```

**Response 200 — 执行类 (INSERT / UPDATE / DELETE)**

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.type` | string | 固定 `"execute"` |
| `data.rowsAffected` | number | 影响行数 |
| `data.lastInsertId` | number | 最后插入的 rowid（INSERT 时有效） |

**示例：**
```json
{
  "success": true,
  "data": {
    "type": "execute",
    "rowsAffected": 1,
    "lastInsertId": 102
  }
}
```

---

## 2. 表结构 (Schema)

### 2.1 获取所有表

| 项目 | 说明 |
|------|------|
| **Method** | `GET` |
| **Path** | `/api/v1/tables` |
| **Query** | 无 |

**Response 200**

| 字段 | 类型 | 说明 |
|------|------|------|
| `data` | array | 元素见下 |
| `data[].name` | string | 表/视图名 |
| `data[].type` | string | `"table"` / `"view"` / `"system"` |

**示例：**
```json
{
  "success": true,
  "data": [
    { "name": "users", "type": "table" },
    { "name": "orders", "type": "table" },
    { "name": "sqlite_sequence", "type": "system" }
  ]
}
```

---

### 2.2 获取单表详情 (DDL & 列信息)

| 项目 | 说明 |
|------|------|
| **Method** | `GET` |
| **Path** | `/api/v1/tables/{tableName}/schema` |
| **Path 参数** | `tableName`: 表或视图名 |

**Response 200**

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.name` | string | 表名 |
| `data.sql` | string | 建表/建视图语句 |
| `data.columns` | array | 列信息，见下 |
| `data.columns[].cid` | number | 列序号 |
| `data.columns[].name` | string | 列名 |
| `data.columns[].type` | string | 声明类型，如 `INTEGER`, `TEXT`, `BLOB` |
| `data.columns[].pk` | number | 是否主键 (0/1) |
| `data.columns[].notnull` | number | 是否 NOT NULL (0/1) |

**示例：**
```json
{
  "success": true,
  "data": {
    "name": "users",
    "sql": "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT, age INTEGER)",
    "columns": [
      { "cid": 0, "name": "id", "type": "INTEGER", "pk": 1, "notnull": 1 },
      { "cid": 1, "name": "avatar", "type": "BLOB", "pk": 0, "notnull": 0 }
    ]
  }
}
```

---

## 3. 数据 CRUD (Rows)

所有行级接口均以 **rowid** 作为行的唯一标识（非业务主键），以兼容无主键或复合主键表。

- 列表接口返回中**强制包含 `rowid`**（`SELECT rowid, * FROM ...`）。
- BLOB：小体积以 Base64 返回，大体积返回占位符 `"<BLOB>"`。
- NULL 在 JSON 中为 `null`。

---

### 3.1 查询表数据 (List Rows)

支持分页、排序与简单过滤。

| 项目 | 说明 |
|------|------|
| **Method** | `GET` |
| **Path** | `/api/v1/tables/{tableName}/rows` |
| **Path 参数** | `tableName`: 表名 |
| **Query 参数** | 见下 |

**Query 参数**

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `_page` | number | 1 | 页码 |
| `_per_page` | number | 50 | 每页条数 |
| `_sort` | string | rowid | 排序字段 |
| `_order` | string | ASC | `ASC` / `DESC` |
| `{column_name}` | string | - | 等值过滤，如 `age=20` |
| `_filter` | string | - | 可选，简单 SQL 条件片段（仅建议在 Debug 环境使用） |

**Response 200**

| 字段 | 类型 | 说明 |
|------|------|------|
| `meta.page` | number | 当前页 |
| `meta.per_page` | number | 每页条数 |
| `meta.total_rows` | number | 该表总行数（满足过滤条件时为该条件下的总数） |
| `data.columns` | string[] | 列名，**首列为 rowid** |
| `data.rows` | array[] | 行数据，每行为值数组 |

**示例：**
```json
{
  "success": true,
  "meta": {
    "page": 1,
    "per_page": 50,
    "total_rows": 1024
  },
  "data": {
    "columns": ["rowid", "id", "name", "age"],
    "rows": [
      [101, 1, "Alice", 25],
      [102, 2, "Bob", 30]
    ]
  }
}
```

---

### 3.2 新增行 (Create)

| 项目 | 说明 |
|------|------|
| **Method** | `POST` |
| **Path** | `/api/v1/tables/{tableName}/rows` |
| **Path 参数** | `tableName`: 表名 |
| **Body** | JSON 对象，key 为列名，value 为对应值 |

**Request Body 示例：**
```json
{
  "name": "Charlie",
  "age": 22
}
```

**Response 200**

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.rowid` | number | 新插入行的 rowid |

**示例：**
```json
{
  "success": true,
  "data": { "rowid": 103 }
}
```

---

### 3.3 修改行 (Update，按 rowid)

仅更新传入的字段（PATCH 语义）。

| 项目 | 说明 |
|------|------|
| **Method** | `PUT` |
| **Path** | `/api/v1/tables/{tableName}/rows/{rowid}` |
| **Path 参数** | `tableName`, `rowid`（行唯一标识） |
| **Body** | JSON 对象，仅包含要更新的列 |

**Request Body 示例：**
```json
{
  "age": 23
}
```

**Response 200**

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.rowsAffected` | number | 影响行数（0 或 1） |

**示例：**
```json
{
  "success": true,
  "data": { "rowsAffected": 1 }
}
```

---

### 3.4 删除行 (Delete，按 rowid)

| 项目 | 说明 |
|------|------|
| **Method** | `DELETE` |
| **Path** | `/api/v1/tables/{tableName}/rows/{rowid}` |
| **Path 参数** | `tableName`, `rowid` |

**Response 200**

| 字段 | 类型 | 说明 |
|------|------|------|
| `data.rowsAffected` | number | 影响行数（0 或 1） |

**示例：**
```json
{
  "success": true,
  "data": { "rowsAffected": 1 }
}
```

---

## 4. 错误响应

当 `success` 为 `false` 时，应包含 `error` 对象：

| 字段 | 类型 | 说明 |
|------|------|------|
| `error.code` | string | 机器可读错误码 |
| `error.message` | string | 人类可读或调试用信息 |

**常见错误码（建议）**

| code | HTTP | 说明 |
|------|------|------|
| `db_not_open` | 503 | 数据库未打开 |
| `invalid_table` | 404 | 表不存在 |
| `invalid_rowid` | 404 | 行不存在或 rowid 无效 |
| `bad_request` | 400 | 参数/Body 不合法 |
| `sql_error` | 400 | SQL 执行失败（含 prepare/step 等） |

**示例：**
```json
{
  "success": false,
  "error": {
    "code": "invalid_table",
    "message": "Table not found: unknown_table"
  }
}
```

---

## 5. 接口索引（速查）

| Method | Path | 说明 |
|--------|------|------|
| GET | `/api/v1/db/info` | 数据库信息 |
| GET | `/api/v1/system/info` | 系统与数据库元信息 |
| POST | `/api/v1/db/sql` | 执行原始 SQL |
| GET | `/api/v1/tables` | 所有表 |
| GET | `/api/v1/tables/{tableName}/schema` | 表结构 |
| GET | `/api/v1/tables/{tableName}/rows` | 分页列表 |
| POST | `/api/v1/tables/{tableName}/rows` | 新增行 |
| PUT | `/api/v1/tables/{tableName}/rows/{rowid}` | 更新行 |
| DELETE | `/api/v1/tables/{tableName}/rows/{rowid}` | 删除行 |
