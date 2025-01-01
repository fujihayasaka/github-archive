#!/bin/bash

sudo service mariadb start
sudo mariadb -u root -e "CREATE DATABASE tma_dev"
sudo mariadb -u root -e "CREATE USER tma@localhost identified by \"TMAdevP4ssw0rd\!\""
sudo mariadb -u root -e "GRANT ALL ON tma_dev.* TO tma@localhost WITH GRANT OPTION"

go install -tags mysql github.com/golang-migrate/migrate/v4/cmd/migrate@latest
make dev-migrate-up
make bin/tma
