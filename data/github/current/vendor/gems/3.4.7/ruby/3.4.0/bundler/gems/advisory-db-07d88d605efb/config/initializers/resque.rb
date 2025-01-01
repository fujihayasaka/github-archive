# frozen_string_literal: true

require "resque/failure/multiple"
require "resque/failure/redis"
require "failbot/resque_failure_backend"

Resque::Failure::Multiple.classes = [Resque::Failure::Redis, Resque::Failure::Failbot]
Resque::Failure.backend = Resque::Failure::Multiple

namespace = "advisory-db:#{Rails.env}:resque"
Resque.redis = Redis::Namespace.new(namespace, redis: AdvisoryDB.redis)

Resque.logger.level = Logger::INFO
