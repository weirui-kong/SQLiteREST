
---

# **SQLite WebUI Backend API Documentation**

This document defines a minimal, robust, and practical API specification for interacting with a local SQLite database.
It is designed for lightweight environments such as **iOS + GCDWebServer**, providing table inspection, row browsing, CRUD operations, and raw SQL execution.

All responses follow a unified JSON structure.

---

# **Response Format**

### **Success**

```json
{
  "ok": true,
  "data": { ... }
}
```

### **Error**

```json
{
  "ok": false,
  "error": "error message",
  "code": "ERROR_CODE"
}
```

---

# ----------------------------------------

# **1. List All Tables and Metadata**

# ----------------------------------------

### **Endpoint**

```
GET /api/tables
```

### **Description**

Returns all tables and views in the SQLite database, including column details, primary keys, and whether the table uses a ROWID.

### **Response Example**

```json
{
  "ok": true,
  "data": [
    {
      "name": "users",
      "type": "table",
      "hasRowId": true,
      "primaryKey": ["id"],
      "columns": [
        {
          "name": "id",
          "type": "INTEGER",
          "notnull": true,
          "pk": 1,
          "default": null
        },
        {
          "name": "name",
          "type": "TEXT",
          "notnull": false,
          "pk": 0,
          "default": null
        }
      ]
    },
    {
      "name": "logs_view",
      "type": "view"
    }
  ]
}
```

---

# ----------------------------------------

# **2. List All Rows of a Table (with Optional Filter)**

# ----------------------------------------

### **Endpoint**

```
POST /api/table/{tableName}/rows
```

### **Request Body**

```json
{
  "filter": "age > 18 AND name LIKE '%John%'"
}
```

* `filter` is optional
* If omitted or empty → no filter is applied

### **Response Example**

```json
{
  "ok": true,
  "data": {
    "columns": ["id", "name", "age"],
    "rows": [
      [1, "John Doe", 20],
      [3, "Johnson", 35]
    ]
  }
}
```

---

# ----------------------------------------

# **3. Insert a Row**

# ----------------------------------------

### **Endpoint**

```
POST /api/table/{tableName}/insert
```

### **Request Body**

```json
{
  "row": {
    "name": "Alice",
    "age": 30
  }
}
```

### **Response Example**

```json
{
  "ok": true,
  "data": {
    "insertedRowId": 12
  }
}
```

For WITHOUT ROWID tables:

```json
{
  "insertedRowId": null
}
```

---

# ----------------------------------------

# **4. Update a Row**

# ----------------------------------------

### **Endpoint**

```
POST /api/table/{tableName}/update
```

### **Description**

Updates a row identified by its primary key values.

### **Request Body**

```json
{
  "primaryKey": {
    "id": 3
  },
  "newValues": {
    "name": "New Name",
    "age": 40
  }
}
```

### **Response Example**

```json
{
  "ok": true,
  "data": {
    "rowsAffected": 1
  }
}
```

---

# ----------------------------------------

# **5. Delete a Row**

# ----------------------------------------

### **Endpoint**

```
POST /api/table/{tableName}/delete
```

### **Request Body**

```json
{
  "primaryKey": {
    "id": 10
  }
}
```

### **Response Example**

```json
{
  "ok": true,
  "data": {
    "rowsAffected": 1
  }
}
```

---

# ----------------------------------------

# **6. Execute Raw SQL**

# ----------------------------------------

### **Endpoint**

```
POST /api/sql
```

### **Request Body**

```json
{
  "sql": "SELECT id, name FROM users WHERE age > 20;"
}
```

### **Query Result Example**

```json
{
  "ok": true,
  "data": {
    "columns": ["id", "name"],
    "rows": [
      [1, "John"],
      [2, "Alice"]
    ]
  }
}
```

### **Write Operation Result Example**

```json
{
  "ok": true,
  "data": {
    "rowsAffected": 3
  }
}
```

### **Error Example**

```json
{
  "ok": false,
  "error": "syntax error near ...",
  "code": "SQL_EXEC_ERROR"
}
```

---

# **API Summary**

| Feature                | Method | Path                        |
| ---------------------- | ------ | --------------------------- |
| List tables + metadata | GET    | `/api/tables`               |
| List rows              | POST   | `/api/table/{table}/rows`   |
| Insert row             | POST   | `/api/table/{table}/insert` |
| Update row             | POST   | `/api/table/{table}/update` |
| Delete row             | POST   | `/api/table/{table}/delete` |
| Execute SQL            | POST   | `/api/sql`                  |

---
