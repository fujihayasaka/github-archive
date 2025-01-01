# typed: true
# frozen_string_literal: true

ActiveRecord::QueryLogs.taggings = ActiveRecord::QueryLogs.taggings.merge \
  catalog_service:   -> (context) { context[:catalog_service] || "unknown" },
  category:          -> (context) { context[:controller]&.try(:request_category) },
  route:             -> (context) { context[:controller]&.try(:query_logs_route) },
  request_id:        -> (context) { context[:controller]&.try(:env).try(:[], "HTTP_X_GITHUB_REQUEST_ID") },
  job_id:            -> (context) { context[:job].try(:job_id) },
  graphql_operation: -> (context) { context[:graphql_operation] },
  referrer_controller_action: -> (context) { context[:referrer_controller_action] },
  deployed_to:     GitHub.deployed_to,
  server:          ENV.fetch("KUBE_NODE_HOSTNAME", GitHub.hostname),
  "cross-schema-domain-query-exempted": -> (context) { context[:"cross-schema-domain-query-exempted"] },
  "cross-schema-domain-transaction-exempted": -> (context) { context[:"cross-schema-domain-transaction-exempted"] },
  "cross-shard-query-exempted": -> (context) { context[:"cross-shard-query-exempted"] },
  package: -> (context) { context[:package] },
  name: -> (context) { context[:name] }

if GitHub::AppEnvironment.test?
  ActiveRecord::QueryLogs.taggings = ActiveRecord::QueryLogs.taggings.merge \
    run_inside_test: -> {
      Thread.current[:run_inside_test]
    },
    test_name: -> {
      Thread.current[:running_test_name]
    },
    test_phase: -> {
      Thread.current[:test_phase]
    }
end

ActiveRecord::QueryLogs.prepend_comment = ENV["GITHUB_SQL_PREPEND_COMMENT"] == "true"

Rails.application.configure do
  T.bind(self, Rails::Application)

  config.active_record.query_log_tags = [
    { application: "github" },
    :catalog_service,
    :category,
    :route,
    :request_id,
    :job_id,
    :graphql_operation,
    :referrer_controller_action,
    :deployed_to,
    :server,
    :job,
    :"cross-schema-domain-query-exempted",
    :"cross-schema-domain-transaction-exempted",
    :"cross-shard-query-exempted",
    :package,
    :name,
    :run_inside_test,
    :test_name,
    :test_phase,
  ]
end
