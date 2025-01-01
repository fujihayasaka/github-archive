# typed: true
# frozen_string_literal: true

require "rollup"

Rollup.denylist = [
  "<internal:",
  "THE WIRE",
  "packages/git/app/models/git/ref.rb",
  "packages/git/app/models/repository/commits_dependency.rb",
  "packages/git/app/models/repository/refs_dependency.rb",
  "bin/ernicorn",
  "config/ernicorn.rb",
  "config/subscribers/trilogy/transaction_subscriber.rb",
  "config/instrumentation",
  "lib/github/active_record_enumerable_protection.rb",
  "lib/github/active_record_readonly_mode.rb",
  "lib/github/association_instrumenter.rb",
  "lib/github/cache",
  "lib/github/config/mysql.rb",
  "lib/github/config/notifications.rb",
  "lib/github/ds.rb",
  "lib/github/experiment.rb",
  "lib/github/request_timer.rb",
  "lib/github/query_batching/iterator_builder.rb",
  "lib/github/query_batching/scope_iterator.rb",
  "lib/github/sorbet/runtime.rb",
  "lib/github/sql/batched.rb",
  "lib/github/sql/batched_between.rb",
  "packages/substrate/app/models/mysql_transaction_reporter.rb",
  "packages/substrate/app/models/nested_transaction_reporter.rb",
  "vendor/",
  "lib/resilient/trilogy.rb",
  "lib/github/connection_adapter_disabler.rb",
  "lib/github/connection_adapter_telemetry.rb",
  "lib/github/json/active_support_patch.rb",
  "lib/github/json.rb"
]
