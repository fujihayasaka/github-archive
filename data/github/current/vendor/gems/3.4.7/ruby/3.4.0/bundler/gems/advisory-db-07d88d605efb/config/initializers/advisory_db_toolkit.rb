# frozen_string_literal: true

require "advisory_db_toolkit"

AdvisoryDBToolkit.logger = GitHub::Telemetry::Logs.logger
AdvisoryDBToolkit.cache = AdvisoryDB.redis
AdvisoryDBToolkit.cache_prefix_key = "advisory_database"
