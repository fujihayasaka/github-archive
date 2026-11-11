# frozen_string_literal: true

require "hydro"
require "hydro/datadog_reporter"

Hydro.load_schemas("vendor/hydro")

Hydro::DatadogReporter.start(dogstatsd: AdvisoryDB.stats, client_id: AdvisoryDB.kafka_client_id)
