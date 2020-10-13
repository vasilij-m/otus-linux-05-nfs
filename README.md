### Задание

   Vagrant up должен поднимать 2 виртуалки: сервер и клиент
   на сервер должна быть расшарена директория
   на клиента она должна автоматически монтироваться при старте (fstab или autofs)
   в шаре должна быть папка upload с правами на запись
   - требования для NFS: NFSv3 по UDP, включенный firewall

   \* Настроить аутентификацию через KERBEROS

---

## Выполнение задания

Так как Kerberos аутентификация была реализована в NFSv4, мной была выполнена настройка NFSv4 по TCP (UDP не поддерживается в NFSv4). Я пытался реализовать NFSv3 с Kerberos аутентификацией по UDP, так как в итоге поддержку Kerberos добавили и в 3ю версию NFS, но у меня получилось подключить шару только по TCP. Возможно по UDP такое решение работать из коробки и не должно, ответа я не нашел.

***Список разворачиваемых виртуальных машин:***

1. krb-srv (192.168.10.30) - сервер Kerberos
2. nfs-srv (192.168.10.10) - сервер NFS
3. nfs-cl (192.168.10.20)) - клиент NFS

На всех машинах запустим firewall:

```
[root@nfs-srv ~]# systemctl enable firewalld --now
```

### 1. Установка и настройка kerberos-аутентификации.

Для службы Kerberos критично точное время, поэтому необходимо его синхронизировать между нашими серверами. 

Для начала изменим временную зону на всех серверах:

```
[root@nfs-srv ~]# timedatectl set-timezone Europe/Moscow
```

На всех серверах установим службу `ntp`, запустим её и разрешим на файрволле:

```
[root@nfs-srv ~]# yum install -y ntp
[root@nfs-srv ~]# systemctl enable ntpd --now
[root@nfs-srv ~]# firewall-cmd --permanent --add-service=ntp
success
[root@nfs-srv ~]# firewall-cmd --reload 
success
```

Изменим имена наших серверов в формате `<hostname>.nfs.lab`:

```
[root@nfs-srv ~]# hostnamectl set-hostname nfs-srv.nfs.lab
```

Для корректной работы служб kerberos необходимо в файле `/etc/hosts` прописать FQDN наших серверов с их реальными IP адресами:

```
[root@nfs-srv ~]# cat /etc/hosts
192.168.10.10	nfs-srv.nfs.lab	nfs-srv
192.168.10.20	nfs-cl.nfs.lab	nfs-cl
192.168.10.30	krb-srv.nfs.lab	krb-srv
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
```

**Конфигурация KDC сервера (krb-srv)**

Установим пакеты:

```
[root@krb-srv ~]# yum install -y krb5-server krb5-libs krb5-workstation
```

Изменим в конфигурационных файлах `/etc/krb5.conf` и `/var/kerberos/krb5kdc/kdc.conf` все, что связано с realm:

```
[root@krb-srv ~]# cat /etc/krb5.conf
# Configuration snippets may be placed in this directory as well
includedir /etc/krb5.conf.d/

[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 pkinit_anchors = FILE:/etc/pki/tls/certs/ca-bundle.crt
 default_realm = NFS.LAB
 default_ccache_name = KEYRING:persistent:%{uid}

[realms]
 NFS.LAB = {
  kdc = krb-srv.nfs.lab
  admin_server = krb-srv.nfs.lab
 }

[domain_realm]
 .nfs.lab = NFS.LAB
 nfs.lab = NFS.LAB
```

```
[root@krb-srv ~]# cat /var/kerberos/krb5kdc/kdc.conf 
[kdcdefaults]
 kdc_ports = 88
 kdc_tcp_ports = 88

[realms]
 NFS.LAB = {
  master_key_type = aes256-cts
  acl_file = /var/kerberos/krb5kdc/kadm5.acl
  dict_file = /usr/share/dict/words
  admin_keytab = /var/kerberos/krb5kdc/kadm5.keytab
  supported_enctypes = aes256-cts:normal aes128-cts:normal des3-hmac-sha1:normal arcfour-hmac:normal camellia256-cts:normal camellia128-cts:normal des-hmac-sha1:normal des-cbc-md5:normal des-cbc-crc:normal
 }
```

Отредактируем файл `/var/kerberos/krb5kdc/kadm5.acl`, который определяет, какие принципалы с каким уровнем прав имеют административный доступ к базе данных Kerberos:

```
[root@krb-srv ~]# cat /var/kerberos/krb5kdc/kadm5.acl 
*/admin@NFS.LAB	*
```

Создадим базу данных Kerberos, укажем KDC database master key (M@sterKey):

```
[root@krb-srv ~]# kdb5_util create -s
Loading random data
Initializing database '/var/kerberos/krb5kdc/principal' for realm 'NFS.LAB',
master key name 'K/M@NFS.LAB'
You will be prompted for the database Master Password.
It is important that you NOT FORGET this password.
Enter KDC database master key: 
Re-enter KDC database master key to verify:
```

Создадим принципал `root/admin` с паролем `r00tp@ss`:

```
[root@krb-srv ~]# kadmin.local -q "addprinc -pw r00tp@ss root/admin"
Authenticating as principal root/admin@NFS.LAB with password.
WARNING: no policy specified for root/admin@NFS.LAB; defaulting to no policy
Principal "root/admin@NFS.LAB" created.
```

Также создадим обычного юзера `nfs_user` с паролем `nfsp@ss`:

```
[root@krb-srv ~]# kadmin.local -q "addprinc -pw nfsp@ss nfs_user"
Authenticating as principal root/admin@NFS.LAB with password.
WARNING: no policy specified for nfs_user@NFS.LAB; defaulting to no policy
Principal "nfs_user@NFS.LAB" created.
```

Добавим парвила для firewalld:

```
[root@krb-srv ~]# firewall-cmd --add-service=kerberos --permanent 
success
[root@krb-srv ~]# firewall-cmd --add-service=kadmin --permanent 
success
[root@krb-srv ~]# firewall-cmd --reload 
success
```

Запустим сервисы Kerberos:
```
[root@krb-srv ~]# systemctl start krb5kdc.service kadmin.service 
[root@krb-srv ~]# systemctl enable krb5kdc.service kadmin.service 
Created symlink from /etc/systemd/system/multi-user.target.wants/krb5kdc.service to /usr/lib/systemd/system/krb5kdc.service.
Created symlink from /etc/systemd/system/multi-user.target.wants/kadmin.service to /usr/lib/systemd/system/kadmin.service.
```

Удостоверимся, что KDC выдает билеты. Для этого аутентифицируемся под пользователем nfs_user и проверим наличие билета:

```
[root@krb-srv ~]# kinit nfs_user
Password for nfs_user@NFS.LAB: 
[root@krb-srv ~]# klist
Ticket cache: KEYRING:persistent:0:0
Default principal: nfs_user@NFS.LAB

Valid starting     Expires            Service principal
10/04/20 20:56:01  10/05/20 20:56:01  krbtgt/NFS.LAB@NFS.LAB
```

**Конфигурация KDC клиентов (nfs-srv, nfs-cl)**

Установим пакеты:

```
[root@nfs-srv ~]# yum install -y krb5-workstation krb5-libs
```

Отредактируем на клиентах файл `/etc/krb5.conf`:

```
[root@nfs-srv ~]# cat /etc/krb5.conf
# Configuration snippets may be placed in this directory as well
includedir /etc/krb5.conf.d/

[logging]
 default = FILE:/var/log/krb5libs.log
 kdc = FILE:/var/log/krb5kdc.log
 admin_server = FILE:/var/log/kadmind.log

[libdefaults]
 dns_lookup_realm = false
 ticket_lifetime = 24h
 renew_lifetime = 7d
 forwardable = true
 rdns = false
 pkinit_anchors = FILE:/etc/pki/tls/certs/ca-bundle.crt
 default_realm = NFS.LAB
 default_ccache_name = KEYRING:persistent:%{uid}

[realms]
 NFS.LAB = {
  kdc = krb-srv.nfs.lab
  admin_server = krb-srv.nfs.lab
 }

[domain_realm]
 .nfs.lab = NFS.LAB
 nfs.lab = NFS.LAB
```

Используя утилиту `kadmin` добавим host-принципалы серверов в базу Kerberos:

```
[root@nfs-cl ~]# kadmin -p root/admin -w r00tp@ss -q "addprinc -randkey host/nfs-cl.nfs.lab"
Authenticating as principal root/admin with password.
WARNING: no policy specified for host/nfs-cl.nfs.lab@NFS.LAB; defaulting to no policy
Principal "host/nfs-cl.nfs.lab@NFS.LAB" created.
```
```
[root@nfs-srv ~]# kadmin -p root/admin -w r00tp@ss -q "addprinc -randkey host/nfs-srv.nfs.lab"
Authenticating as principal root/admin with password.
WARNING: no policy specified for host/nfs-srv.nfs.lab@NFS.LAB; defaulting to no policy
Principal "host/nfs-srv.nfs.lab@NFS.LAB" created.
```

Затем на клиентах Kerberos нужно извлечь ключи принципала и записать их в `keytab` файл, добавленные в предыдущем шаге с помощью опции `-randkey`:

```
[root@nfs-srv ~]# kadmin -p root/admin -w r00tp@ss -q "ktadd -k /etc/krb5.keytab host/nfs-srv.nfs.lab"
Authenticating as principal root/admin with password.
Entry for principal host/nfs-srv.nfs.lab with kvno 2, encryption type aes256-cts-hmac-sha1-96 added to keytab WRFILE:/etc/krb5.keytab.
...
```
```
[root@nfs-cl ~]# kadmin -p root/admin -w r00tp@ss -q "ktadd -k /etc/krb5.keytab host/nfs-cl.nfs.lab"
Authenticating as principal root/admin with password.
Entry for principal host/nfs-cl.nfs.lab with kvno 2, encryption type aes256-cts-hmac-sha1-96 added to keytab WRFILE:/etc/krb5.keytab.
...
```

С сервера `nfs-srv` зарегистрируем сервис NFS в качестве принципала в базе Kerberos и сохраним соотвествующий ей ключ, после чего перезапустим серивс `nfs-server`:

```
[root@nfs-srv ~]# kadmin -p root/admin -w r00tp@ss -q "addprinc -randkey nfs/nfs-srv.nfs.lab"
Authenticating as principal root/admin with password.
WARNING: no policy specified for nfs/nfs-srv.nfs.lab@NFS.LAB; defaulting to no policy
Principal "nfs/nfs-srv.nfs.lab@NFS.LAB" created.
[root@nfs-srv ~]# 
[root@nfs-srv ~]# kadmin -p root/admin -w r00tp@ss -q "ktadd nfs/nfs-srv.nfs.lab"
Authenticating as principal root/admin with password.
Entry for principal nfs/nfs-srv.nfs.lab with kvno 2, encryption type aes256-cts-hmac-sha1-96 added to keytab FILE:/etc/krb5.keytab.
...
[root@nfs-srv ~]# 
[root@nfs-srv ~]# systemctl restart nfs-server
```

Повторим на `nfs-cl`:

```
[root@nfs-cl ~]# kadmin -p root/admin -w r00tp@ss -q "addprinc -randkey nfs/nfs-cl.nfs.lab"
Authenticating as principal root/admin with password.
WARNING: no policy specified for nfs/nfs-cl.nfs.lab@NFS.LAB; defaulting to no policy
Principal "nfs/nfs-cl.nfs.lab@NFS.LAB" created.
[root@nfs-cl ~]# 
[root@nfs-cl ~]# kadmin -p root/admin -w r00tp@ss -q "ktadd nfs/nfs-cl.nfs.lab"
Authenticating as principal root/admin with password.
Entry for principal nfs/nfs-cl.nfs.lab with kvno 2, encryption type aes256-cts-hmac-sha1-96 added to keytab FILE:/etc/krb5.keytab.
...
[root@nfs-cl ~]# 
[root@nfs-cl ~]# systemctl restart nfs-client.target
```

### 2. Установка и настройка сервера NFS.

Установим пакет `nfs-utils`:

```
[root@nfs-srv ~]# yum install -y nfs-utils
```

Зупустим нужные сервисы:

```
[root@nfs-srv ~]# systemctl enable nfs --now
Created symlink from /etc/systemd/system/multi-user.target.wants/nfs-server.service to /usr/lib/systemd/system/nfs-server.service.
[root@nfs-srv ~]# systemctl enable nfs-lock --now
[root@nfs-srv ~]# systemctl enable rpcbind --now
```

Включим `firewalld` и откроем порты для сервисов NFS:

```
[root@nfs-srv ~]# systemctl enable firewalld --now
Created symlink from /etc/systemd/system/dbus-org.fedoraproject.FirewallD1.service to /usr/lib/systemd/system/firewalld.service.
Created symlink from /etc/systemd/system/multi-user.target.wants/firewalld.service to /usr/lib/systemd/system/firewalld.service.
[root@nfs-srv ~]# firewall-cmd --permanent --add-service=mountd 
success
[root@nfs-srv ~]# firewall-cmd --permanent --add-service=rpc-bind 
success
[root@nfs-srv ~]# firewall-cmd --permanent --add-service=nfs
success
[root@nfs-srv ~]# firewall-cmd --reload 
success
[root@nfs-srv ~]# firewall-cmd --list-all
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: eth0 eth1
  sources: 
  services: dhcpv6-client mountd nfs rpc-bind ssh
  ports: 
  protocols: 
  masquerade: no
  forward-ports: 
  source-ports: 
  icmp-blocks: 
  rich rules: 
	
```

Создадим директорию /media/nfs_share:

```
[root@nfs-srv ~]# mkdir -p /media/nfs_share/upload
[root@nfs-srv ~]# chown -R nfsnobody:nfsnobody /media/nfs_share/
[root@nfs-srv ~]# chmod -R 777 /media/nfs_share/
```

Изменим файл `/etc/exports`, чтобы расшарить директорию `/media/nfs_share/` с правами на запись и kerberos-аутентификацией, и перезапустим nfs-server:

```
[root@nfs-srv ~]# cat /etc/exports
/media/nfs_share 192.168.10.0/24(rw,sec=krb5)
[root@nfs-srv ~]# systemctl restart nfs-server
```

### 3. Подключение к NFS шаре на клиенте.

Для начала протестируем монтирование:

```
[root@nfs-cl ~]# mkdir /media/nfs_share
[root@nfs-cl ~]# mount -v -t nfs -o vers=4,sec=krb5,proto=tcp nfs-srv.nfs.lab:/media/nfs_share /media/nfs_share
mount.nfs: timeout set for Sat Oct 10 15:46:09 2020
mount.nfs: trying text-based options 'sec=krb5,proto=tcp,vers=4.1,addr=192.168.10.10,clientaddr=192.168.10.20'
[root@nfs-cl ~]#
[root@nfs-cl ~]# mount | grep nfs-srv
nfs-srv.nfs.lab:/media/nfs_share on /media/nfs_share type nfs4 (rw,relatime,vers=4.1,rsize=131072,wsize=131072,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=krb5,clientaddr=192.168.10.20,local_lock=none,addr=192.168.10.10)
[root@nfs-cl ~]#
[root@nfs-cl ~]# klist
Ticket cache: KEYRING:persistent:0:krb_ccache_WBKU6My
Default principal: host/nfs-cl.nfs.lab@NFS.LAB

Valid starting     Expires            Service principal
01/01/70 03:00:00  01/01/70 03:00:00  Encrypted/Credentials/v1@X-GSSPROXY:
```
Видим, что монтирование проходит успешно, при этом для аутентификации используется Kerberos-билет host-принципала.

Проверим, что директория `/media/nfs_share/upload` доступна с правами rw:

```
[root@nfs-cl ~]# ll /media/nfs_share/
total 0
drwxrwxrwx. 2 nfsnobody nfsnobody 18 Oct 10 15:45 upload
[root@nfs-cl ~]# echo "BlaBlaBla" > /media/nfs_share/upload/test
[root@nfs-cl ~]# cat /media/nfs_share/upload/test 
BlaBlaBla
```

***Теперь настроим автомонтирование с помощью systemd.***

В директории `/etc/systemd/system/` создадим systemd юнит `media-nfs_share.mount` со следующим содержимым:

```
[root@nfs-cl ~]# cat /etc/systemd/system/media-nfs_share.mount
[Unit]
Description=Mount NFS Share
Requires=network-online.service
After=network-online.service

[Mount]
What=nfs-srv.nfs.lab:/media/nfs_share
Where=/media/nfs_share
Type=nfs
Options=vers=4,sec=krb5,proto=tcp

[Install]
WantedBy=multi-user.target
```

После чего перечитаем конфигурацию systemd и добавим созданный mount unit в автозагрузку:

```
[root@nfs-cl ~]# systemctl daemon-reload
[root@nfs-cl ~]# systemctl enable media-nfs_share.mount
```

После следующих перезагрузок шара будет автоматически монтироваться.


## Проверка задания

**Requirements:**
***Перед проверкой задания необходимо установить плагин vagrant-vbguest: `vagrant plugin install vagrant-vbguest`.***

1. Выполнить `vagrant up`.

2. Подключиться к NFS-серверу `vagrant ssh nfs-srv`:

Просмотр опций NFS-шары:

```
[root@nfs-srv ~]# exportfs -v
/media/nfs_share
		192.168.10.0/24(sync,wdelay,hide,no_subtree_check,sec=krb5,rw,secure,root_squash,no_all_squash)
```

Просмотр подключенных клиентов:

```
[root@nfs-srv ~]# ss | grep nfs
tcp    ESTAB      0      0      192.168.10.10:nfs                  192.168.10.20:733
```

3. Подключиться к NFS-клиенту `vagrant ssh nfs-cl`:

Убедиться, что шара примонтировалась c Kerberos-аутентификацией:

```
[root@nfs-cl ~]# mount | grep nfs-srv
nfs-srv.nfs.lab:/media/nfs_share on /media/nfs_share type nfs4 (rw,relatime,vers=4.1,rsize=131072,wsize=131072,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=krb5,clientaddr=192.168.10.20,local_lock=none,addr=192.168.10.10)
```

Посмотреть наличие билетов Kerberos и содержимое keytab-файла:

```
[root@nfs-cl ~]# klist
Ticket cache: KEYRING:persistent:0:krb_ccache_XN4IkPl
Default principal: host/nfs-cl.nfs.lab@NFS.LAB

Valid starting     Expires            Service principal
01/01/70 03:00:00  01/01/70 03:00:00  Encrypted/Credentials/v1@X-GSSPROXY:
[root@nfs-cl ~]# 
[root@nfs-cl ~]# 
[root@nfs-cl ~]# klist -k
Keytab name: FILE:/etc/krb5.keytab
KVNO Principal
---- --------------------------------------------------------------------------
   2 host/nfs-cl.nfs.lab@NFS.LAB
   2 host/nfs-cl.nfs.lab@NFS.LAB
   2 host/nfs-cl.nfs.lab@NFS.LAB
   2 host/nfs-cl.nfs.lab@NFS.LAB
   2 host/nfs-cl.nfs.lab@NFS.LAB
   2 host/nfs-cl.nfs.lab@NFS.LAB
   2 host/nfs-cl.nfs.lab@NFS.LAB
   2 host/nfs-cl.nfs.lab@NFS.LAB
   2 nfs/nfs-cl.nfs.lab@NFS.LAB
   2 nfs/nfs-cl.nfs.lab@NFS.LAB
   2 nfs/nfs-cl.nfs.lab@NFS.LAB
   2 nfs/nfs-cl.nfs.lab@NFS.LAB
   2 nfs/nfs-cl.nfs.lab@NFS.LAB
   2 nfs/nfs-cl.nfs.lab@NFS.LAB
   2 nfs/nfs-cl.nfs.lab@NFS.LAB
   2 nfs/nfs-cl.nfs.lab@NFS.LAB
```
 
Записать что-нибудь в директорию `/media/nfs_share/upload`:

```
[root@nfs-cl ~]# echo "BlaBlaBla" > /media/nfs_share/upload/test
[root@nfs-cl ~]# cat /media/nfs_share/upload/test 
BlaBlaBla
```

Перезагрузить машину nfs-cl и убедиться, что автомонтирование работает.


Доступ к директории `/media/nfs_share` не из под рута можно получить, если запросить билет Kerberos от имени пользователя ***nfs_user*** (`kinit nfs_user`) и введя пароль ***nfsp@ss***.








