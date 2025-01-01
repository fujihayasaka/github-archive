This folder can start up a local statsd server, which you can use in conjunction with the puma statsd logger (and probably other statsd logging by overriding other env vars)

To get puma's statsd to report, first run `start.sh` in one terminal, then run `STATSD_HOST=127.0.0.1 STATSD_PORT=8125 RAILS_LOG_TO_STDOUT=true bundle exec puma -C config/puma.rb` .
