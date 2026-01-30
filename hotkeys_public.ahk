:*:@ip::$(Invoke-RestMethod -Uri "http://ip-api.com/json/").query
:o:ss1::ss -ltnp | grep :
:o:scp1::scp -r -P 22 /etc/redis.conf root@8.148.254.178:/deploy/
:o:mvn1::mvn clean package -DskipTests
:o:alt1::ALTER TABLE table_name MODIFY COLUMN col_name VARCHAR(50) DEFAULT NULL;
:o:alt2::ALTER TABLE table_name ADD COLUMN col_name VARCHAR(50) DEFAULT NULL;
:o:alt3::ALTER TABLE table_name CHANGE old_name new_name VARCHAR(50) DEFAULT NULL;
:o:sel1::SELECT * FROM table_name
:o:sel2::SELECT * FROM table_name where col_name = ''
:o:show1::SHOW CREATE TABLE table_name
:o:cre1::CREATE UNIQUE INDEX `uk_group_code` ON lms_group (code) USING BTREE
:o:log::console.log()
:*:tr0::truncate -s 0
:*:ord::ORDER BY update_time desc
:*:chcp1::chcp 65001

;~ sql事务
:*:st1::
{
    backup := A_Clipboard
    A_Clipboard := "START TRANSACTION;`n`nCOMMIT;`nROLLBACK;" ; sql事务
    ;~ ClipWait 0.3
    SendEvent "{Ctrl Down}{v}{Ctrl Up}"
    Sleep 100
    A_Clipboard := backup
}
;~ 数据库死锁
:*:@lock::
{
    ;sqlText := "1`n2`n3"
    ;SendText sqlText;
    ;2. 定义热字符串，使用这个变量
    ;Hotstring(":*:@sql", sqlText)
    SendText "-- 数据库解死锁`n"  ; `n代表换行 .代表连接符
    SendText "select trx_mysql_thread_id ,CONCAT('kill ',trx_mysql_thread_id,';')`n"
    SendText "from information_schema.innodb_trx`n"
    SendText "where TIME_TO_SEC(timediff(now(),trx_started))>20;"
}

:o:net::netstat -tulnp | grep :8080     ;用 o选项去除多余空格
;~ 获取当前时间
:*:cdate::
{
SendText FormatTime(, "yyyy-MM-dd HH:mm:ss") ; 动态计算并发送当前时间
return
}