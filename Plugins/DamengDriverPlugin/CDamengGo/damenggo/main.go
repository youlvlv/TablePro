package main

/*
#include <stdlib.h>
#include <stdint.h>

typedef struct {
    char** names;
    char** typeNames;
    int*   nullables;
    int    count;
} ColumnInfoArray;

typedef struct {
    char** values;
    int*   lengths;
    int*   isNull;
    int    count;
} RowData;
*/
import "C"
import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"sync"
	"time"
	"unsafe"

	_ "dm"
)

var (
	connMu  sync.Mutex
	conns   = map[uintptr]*sql.DB{}
	connSeq uintptr

	rowsMu  sync.Mutex
	rowsMap = map[uintptr]*sql.Rows{}
	rowsSeq uintptr

	txMu  sync.Mutex
	txMap = map[uintptr]*sql.Tx{}
	txSeq uintptr
)

func newConnHandle(db *sql.DB) unsafe.Pointer {
	connMu.Lock()
	defer connMu.Unlock()
	connSeq++
	conns[connSeq] = db
	return unsafe.Pointer(connSeq)
}

func getConn(p unsafe.Pointer) *sql.DB {
	connMu.Lock()
	defer connMu.Unlock()
	return conns[uintptr(p)]
}

func removeConn(p unsafe.Pointer) {
	connMu.Lock()
	defer connMu.Unlock()
	delete(conns, uintptr(p))
}

func newRowsHandle(rs *sql.Rows) unsafe.Pointer {
	rowsMu.Lock()
	defer rowsMu.Unlock()
	rowsSeq++
	rowsMap[rowsSeq] = rs
	return unsafe.Pointer(rowsSeq)
}

func getRows(p unsafe.Pointer) *sql.Rows {
	rowsMu.Lock()
	defer rowsMu.Unlock()
	return rowsMap[uintptr(p)]
}

func removeRows(p unsafe.Pointer) {
	rowsMu.Lock()
	defer rowsMu.Unlock()
	delete(rowsMap, uintptr(p))
}

func newTxHandle(tx *sql.Tx) unsafe.Pointer {
	txMu.Lock()
	defer txMu.Unlock()
	txSeq++
	txMap[txSeq] = tx
	return unsafe.Pointer(txSeq)
}

func getTx(p unsafe.Pointer) *sql.Tx {
	txMu.Lock()
	defer txMu.Unlock()
	return txMap[uintptr(p)]
}

func removeTx(p unsafe.Pointer) {
	txMu.Lock()
	defer txMu.Unlock()
	delete(txMap, uintptr(p))
}

func cstr(s string) *C.char {
	if s == "" {
		return nil
	}
	return C.CString(s)
}

func errStr(err error) *C.char {
	if err == nil {
		return nil
	}
	return C.CString(err.Error())
}

//export DamengOpen
func DamengOpen(dsn *C.char) (unsafe.Pointer, *C.char) {
	dsnStr := C.GoString(dsn)
	db, err := sql.Open("dm", dsnStr)
	if err != nil {
		return nil, errStr(err)
	}
	db.SetMaxOpenConns(1)
	db.SetMaxIdleConns(1)
	db.SetConnMaxLifetime(0)

	ctx, cancel := withTimeout()
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		db.Close()
		return nil, errStr(err)
	}

	h := newConnHandle(db)
	return h, nil
}

//export DamengClose
func DamengClose(conn unsafe.Pointer) {
	db := getConn(conn)
	if db != nil {
		db.Close()
		removeConn(conn)
	}
}

//export DamengPing
func DamengPing(conn unsafe.Pointer) *C.char {
	db := getConn(conn)
	if db == nil {
		return C.CString("not connected")
	}
	ctx, cancel := withTimeout()
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		return errStr(err)
	}
	return nil
}

//export DamengBeginTx
func DamengBeginTx(conn unsafe.Pointer) (unsafe.Pointer, *C.char) {
	db := getConn(conn)
	if db == nil {
		return nil, C.CString("not connected")
	}
	ctx, cancel := withTimeout()
	defer cancel()
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return nil, errStr(err)
	}
	h := newTxHandle(tx)
	return h, nil
}

//export DamengCommitTx
func DamengCommitTx(txHandle unsafe.Pointer) *C.char {
	tx := getTx(txHandle)
	if tx == nil {
		return C.CString("invalid transaction")
	}
	defer removeTx(txHandle)
	if err := tx.Commit(); err != nil {
		return errStr(err)
	}
	return nil
}

//export DamengRollbackTx
func DamengRollbackTx(txHandle unsafe.Pointer) *C.char {
	tx := getTx(txHandle)
	if tx == nil {
		return C.CString("invalid transaction")
	}
	defer removeTx(txHandle)
	if err := tx.Rollback(); err != nil {
		return errStr(err)
	}
	return nil
}

//export DamengQuery
func DamengQuery(conn unsafe.Pointer, sqlStr *C.char) (unsafe.Pointer, *C.char) {
	db := getConn(conn)
	if db == nil {
		return nil, C.CString("not connected")
	}
	query := C.GoString(sqlStr)
	ctx, cancel := withTimeout()
	defer cancel()
	rs, err := db.QueryContext(ctx, query)
	if err != nil {
		return nil, errStr(err)
	}
	h := newRowsHandle(rs)
	return h, nil
}

//export DamengQueryWithParams
func DamengQueryWithParams(conn unsafe.Pointer, sqlStr *C.char, paramCount C.int, paramValues **C.char) (unsafe.Pointer, *C.char) {
	db := getConn(conn)
	if db == nil {
		return nil, C.CString("not connected")
	}
	query := C.GoString(sqlStr)
	params := goStrings(paramCount, paramValues)
	args := make([]interface{}, len(params))
	for i, p := range params {
		args[i] = p
	}
	ctx, cancel := withTimeout()
	defer cancel()
	rs, err := db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, errStr(err)
	}
	h := newRowsHandle(rs)
	return h, nil
}

//export DamengExec
func DamengExec(conn unsafe.Pointer, sqlStr *C.char) (C.int64_t, *C.char) {
	db := getConn(conn)
	if db == nil {
		return -1, C.CString("not connected")
	}
	query := C.GoString(sqlStr)
	ctx, cancel := withTimeout()
	defer cancel()
	result, err := db.ExecContext(ctx, query)
	if err != nil {
		return -1, errStr(err)
	}
	affected, _ := result.RowsAffected()
	return C.int64_t(affected), nil
}

//export DamengExecWithParams
func DamengExecWithParams(conn unsafe.Pointer, sqlStr *C.char, paramCount C.int, paramValues **C.char) (C.int64_t, *C.char) {
	db := getConn(conn)
	if db == nil {
		return -1, C.CString("not connected")
	}
	query := C.GoString(sqlStr)
	params := goStrings(paramCount, paramValues)
	args := make([]interface{}, len(params))
	for i, p := range params {
		args[i] = p
	}
	ctx, cancel := withTimeout()
	defer cancel()
	result, err := db.ExecContext(ctx, query, args...)
	if err != nil {
		return -1, errStr(err)
	}
	affected, _ := result.RowsAffected()
	return C.int64_t(affected), nil
}

//export DamengRowsNext
func DamengRowsNext(rowsHandle unsafe.Pointer) C.int {
	rs := getRows(rowsHandle)
	if rs == nil {
		return -1
	}
	if rs.Next() {
		return 1
	}
	if err := rs.Err(); err != nil {
		return -1
	}
	return 0
}

//export DamengRowsColumnCount
func DamengRowsColumnCount(rowsHandle unsafe.Pointer) C.int {
	rs := getRows(rowsHandle)
	if rs == nil {
		return 0
	}
	cols, err := rs.Columns()
	if err != nil {
		return 0
	}
	return C.int(len(cols))
}

//export DamengRowsColumnNames
func DamengRowsColumnNames(rowsHandle unsafe.Pointer) **C.char {
	rs := getRows(rowsHandle)
	if rs == nil {
		return nil
	}
	cols, err := rs.ColumnTypes()
	if err != nil {
		return nil
	}
	count := len(cols)
	cNames := C.malloc(C.size_t(count) * C.size_t(unsafe.Sizeof(uintptr(0))))
	nameSlice := (*[1 << 20]*C.char)(cNames)[:count:count]
	for i, ct := range cols {
		nameSlice[i] = C.CString(ct.Name())
	}
	return (**C.char)(cNames)
}

//export DamengRowsColumnTypeNames
func DamengRowsColumnTypeNames(rowsHandle unsafe.Pointer) **C.char {
	rs := getRows(rowsHandle)
	if rs == nil {
		return nil
	}
	cols, err := rs.ColumnTypes()
	if err != nil {
		return nil
	}
	count := len(cols)
	cNames := C.malloc(C.size_t(count) * C.size_t(unsafe.Sizeof(uintptr(0))))
	nameSlice := (*[1 << 20]*C.char)(cNames)[:count:count]
	for i, ct := range cols {
		nameSlice[i] = C.CString(ct.DatabaseTypeName())
	}
	return (**C.char)(cNames)
}

//export DamengRowsScanText
func DamengRowsScanText(rowsHandle unsafe.Pointer) **C.char {
	rs := getRows(rowsHandle)
	if rs == nil {
		return nil
	}
	cols, err := rs.Columns()
	if err != nil {
		return nil
	}
	count := len(cols)
	values := make([]sql.NullString, count)
	ptrs := make([]interface{}, count)
	for i := range values {
		ptrs[i] = &values[i]
	}
	if err := rs.Scan(ptrs...); err != nil {
		return nil
	}
	cValues := C.malloc(C.size_t(count) * C.size_t(unsafe.Sizeof(uintptr(0))))
	valSlice := (*[1 << 20]*C.char)(cValues)[:count:count]
	for i, v := range values {
		if v.Valid {
			valSlice[i] = C.CString(v.String)
		} else {
			valSlice[i] = nil
		}
	}
	return (**C.char)(cValues)
}

//export DamengRowsScanRaw
func DamengRowsScanRaw(rowsHandle unsafe.Pointer, outIsNull *C.int) **C.char {
	rs := getRows(rowsHandle)
	if rs == nil {
		return nil
	}
	cols, err := rs.Columns()
	if err != nil {
		return nil
	}
	count := len(cols)
	rawValues := make([][]byte, count)
	ptrs := make([]interface{}, count)
	for i := range rawValues {
		ptrs[i] = &rawValues[i]
	}
	if err := rs.Scan(ptrs...); err != nil {
		return nil
	}
	cValues := C.malloc(C.size_t(count) * C.size_t(unsafe.Sizeof(uintptr(0))))
	valSlice := (*[1 << 20]*C.char)(cValues)[:count:count]
	nullSlice := (*[1 << 20]C.int)(unsafe.Pointer(outIsNull))[:count:count]
	for i, v := range rawValues {
		if v == nil {
			valSlice[i] = nil
			nullSlice[i] = 1
		} else {
			valSlice[i] = C.CString(string(v))
			nullSlice[i] = 0
		}
	}
	return (**C.char)(cValues)
}

//export DamengRowsClose
func DamengRowsClose(rowsHandle unsafe.Pointer) {
	rs := getRows(rowsHandle)
	if rs != nil {
		rs.Close()
		removeRows(rowsHandle)
	}
}

//export DamengFreeString
func DamengFreeString(s *C.char) {
	if s != nil {
		C.free(unsafe.Pointer(s))
	}
}

//export DamengFreeStringArray
func DamengFreeStringArray(arr **C.char, count C.int) {
	if arr == nil {
		return
	}
	slice := (*[1 << 20]*C.char)(unsafe.Pointer(arr))[:int(count):int(count)]
	for _, s := range slice {
		if s != nil {
			C.free(unsafe.Pointer(s))
		}
	}
	C.free(unsafe.Pointer(arr))
}

type tableInfo struct {
	Name string `json:"name"`
	Type string `json:"type"`
}

//export DamengFetchTables
func DamengFetchTables(conn unsafe.Pointer, schema *C.char) *C.char {
	db := getConn(conn)
	if db == nil {
		return C.CString(`{"error":"not connected"}`)
	}
	schemaStr := C.GoString(schema)
	query := fmt.Sprintf(
		"SELECT TABLE_NAME, 'TABLE' AS TABLE_TYPE FROM ALL_TABLES WHERE OWNER = '%s' UNION ALL SELECT VIEW_NAME, 'VIEW' FROM ALL_VIEWS WHERE OWNER = '%s' ORDER BY 1",
		schemaStr, schemaStr,
	)
	ctx, cancel := withTimeout()
	defer cancel()
	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		return C.CString(fmt.Sprintf(`{"error":"%s"}`, jsonEscape(err.Error())))
	}
	defer rows.Close()
	var tables []tableInfo
	for rows.Next() {
		var name, ttype string
		if err := rows.Scan(&name, &ttype); err != nil {
			continue
		}
		tables = append(tables, tableInfo{Name: name, Type: ttype})
	}
	data, _ := json.Marshal(tables)
	return C.CString(string(data))
}

type columnInfo struct {
	Name         string `json:"name"`
	DataType     string `json:"dataType"`
	IsNullable   bool   `json:"isNullable"`
	IsPrimaryKey bool   `json:"isPrimaryKey"`
}

//export DamengFetchColumns
func DamengFetchColumns(conn unsafe.Pointer, schema *C.char, table *C.char) *C.char {
	db := getConn(conn)
	if db == nil {
		return C.CString(`{"error":"not connected"}`)
	}
	schemaStr := C.GoString(schema)
	tableStr := C.GoString(table)
	query := fmt.Sprintf(`
		SELECT
			c.COLUMN_NAME,
			c.DATA_TYPE,
			c.DATA_LENGTH,
			c.DATA_PRECISION,
			c.DATA_SCALE,
			c.NULLABLE,
			CASE WHEN cc.COLUMN_NAME IS NOT NULL THEN 'Y' ELSE 'N' END AS IS_PK
		FROM ALL_TAB_COLUMNS c
		LEFT JOIN (
			SELECT acc.COLUMN_NAME
			FROM ALL_CONS_COLUMNS acc
			JOIN ALL_CONSTRAINTS ac ON acc.CONSTRAINT_NAME = ac.CONSTRAINT_NAME
				AND acc.OWNER = ac.OWNER
			WHERE ac.CONSTRAINT_TYPE = 'P'
				AND ac.OWNER = '%s'
				AND ac.TABLE_NAME = '%s'
		) cc ON c.COLUMN_NAME = cc.COLUMN_NAME
		WHERE c.OWNER = '%s'
		  AND c.TABLE_NAME = '%s'
		ORDER BY c.COLUMN_ID`,
		schemaStr, tableStr, schemaStr, tableStr,
	)
	ctx, cancel := withTimeout()
	defer cancel()
	rows, err := db.QueryContext(ctx, query)
	if err != nil {
		return C.CString(fmt.Sprintf(`{"error":"%s"}`, jsonEscape(err.Error())))
	}
	defer rows.Close()
	var columns []columnInfo
	for rows.Next() {
		var name, dataType, nullable, isPk string
		var dataLength, dataPrecision, dataScale sql.NullString
		if err := rows.Scan(&name, &dataType, &dataLength, &dataPrecision, &dataScale, &nullable, &isPk); err != nil {
			continue
		}
		fullType := buildFullType(dataType, dataLength, dataPrecision, dataScale)
		columns = append(columns, columnInfo{
			Name:         name,
			DataType:     fullType,
			IsNullable:   nullable == "Y",
			IsPrimaryKey: isPk == "Y",
		})
	}
	data, _ := json.Marshal(columns)
	return C.CString(string(data))
}

//export DamengFetchVersion
func DamengFetchVersion(conn unsafe.Pointer) *C.char {
	db := getConn(conn)
	if db == nil {
		return nil
	}
	ctx, cancel := withTimeout()
	defer cancel()
	var version string
	err := db.QueryRowContext(ctx, "SELECT BANNER FROM V$VERSION WHERE ROWNUM = 1").Scan(&version)
	if err != nil {
		return nil
	}
	return C.CString(version)
}

//export DamengFetchCurrentSchema
func DamengFetchCurrentSchema(conn unsafe.Pointer) *C.char {
	db := getConn(conn)
	if db == nil {
		return nil
	}
	ctx, cancel := withTimeout()
	defer cancel()
	var schema string
	err := db.QueryRowContext(ctx, "SELECT CURRENT_SCHEMA()").Scan(&schema)
	if err != nil {
		return nil
	}
	return C.CString(schema)
}

//export DamengSetSchema
func DamengSetSchema(conn unsafe.Pointer, schema *C.char) *C.char {
	db := getConn(conn)
	if db == nil {
		return C.CString("not connected")
	}
	schemaStr := C.GoString(schema)
	query := fmt.Sprintf(`SET SCHEMA "%s"`, schemaStr)
	ctx, cancel := withTimeout()
	defer cancel()
	_, err := db.ExecContext(ctx, query)
	if err != nil {
		return errStr(err)
	}
	return nil
}

const defaultTimeout = 30 * time.Second

func withTimeout() (context.Context, context.CancelFunc) {
	return context.WithTimeout(context.Background(), defaultTimeout)
}

func goStrings(count C.int, arr **C.char) []string {
	if count == 0 || arr == nil {
		return nil
	}
	slice := (*[1 << 20]*C.char)(unsafe.Pointer(arr))[:int(count):int(count)]
	result := make([]string, int(count))
	for i, s := range slice {
		if s != nil {
			result[i] = C.GoString(s)
		}
	}
	return result
}

func jsonEscape(s string) string {
	b, _ := json.Marshal(s)
	return string(b[1 : len(b)-1])
}

func buildFullType(dataType string, dataLength, dataPrecision, dataScale sql.NullString) string {
	fixedTypes := map[string]bool{
		"date": true, "time": true, "timestamp": true, "datetime": true, "smalldatetime": true,
		"clob": true, "nclob": true, "blob": true, "text": true, "long": true, "long raw": true,
		"rowid": true, "binary": true, "varbinary": true, "longvarbinary": true, "guid": true,
	}
	dt := dataType
	if fixedTypes[dt] {
		return dt
	}
	if dt == "number" || dt == "numeric" || dt == "decimal" {
		if dataPrecision.Valid {
			if p, err := parseint(dataPrecision.String); err == nil {
				if dataScale.Valid {
					if s, err := parseint(dataScale.String); err == nil && s > 0 {
						return fmt.Sprintf("%s(%d,%d)", dt, p, s)
					}
				}
				return fmt.Sprintf("%s(%d)", dt, p)
			}
		}
		return dt
	}
	if dataLength.Valid {
		if l, err := parseint(dataLength.String); err == nil && l > 0 {
			return fmt.Sprintf("%s(%d)", dt, l)
		}
	}
	return dt
}

func parseint(s string) (int, error) {
	var n int
	_, err := fmt.Sscanf(s, "%d", &n)
	return n, err
}

// Required for c-archive buildmode
func main() {
	_ = time.Now()
}
