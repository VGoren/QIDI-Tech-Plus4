# 1. Бэкапим родной список репозиториев (только если бэкапа еще нет)
# Это защитит от перезаписи чистого бэкапа архивными данными при повторном запусте.
[ ! -f /etc/apt/sources.list.bak ] && sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak

# 2. Прописываем архивные зеркала Debian Buster (т.к. основные сервера Debian 10 отключены)
# archive.debian.org — это вечный "замороженный" архив для старых систем.
echo "deb http://archive.debian.org/debian buster main contrib non-free
deb http://archive.debian.org/debian-security buster/updates main contrib non-free" | sudo tee /etc/apt/sources.list

# 3. Убираем проверку Check-Valid-Until для пакетов
# Т.к. репозиторий не обновляется, apt по умолчанию считает его "просроченным" и выдает ошибку.
echo "Acquire::Check-Valid-Until \"false\";" | sudo tee /etc/apt/apt.conf.d/10no--check-valid-until

# 4. Обновляем кеш пакетного менеджера
# После этого можно ставить любые пакеты через apt install (например, samba, htop, git).
sudo apt update


sudo apt install samba -y

# Добавляем права доступа к папке конфигов в основной конфиг Samba
echo "
[QidiConfig]
   comment    = Qidi Plus 4 Configs
   path       = /home/mks/printer_data/config
   browseable = yes
   read only  = no
   guest ok   = no
   force user = mks
" | sudo tee -a /etc/samba/smb.conf