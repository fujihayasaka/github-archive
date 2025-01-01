-- Create a user for replication
CREATE USER 'replica_user'@'%' IDENTIFIED WITH
mysql_native_password BY 'replica_p4ssw0rd';

-- Grant replication privileges
GRANT REPLICATION SLAVE ON *.* TO 'replica_user'@'%';
FLUSH PRIVILEGES;
