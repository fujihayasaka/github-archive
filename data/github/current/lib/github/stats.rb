# typed: true
# frozen_string_literal: true

module GitHub::Stats
  # Time periods buckets
  PERIODS = {
    all: "",
    daily: "%Y:%m:%d",
  }.freeze

  ENTERPRISE_ALLOWLIST = %w(
    unicorn.#{category}.response_time
    unicorn.#{category}.cpu_time
    unicorn.#{category}.idle_time
    unicorn.#{category}.mysql.queries
    unicorn.#{category}.mysql.time
    unicorn.#{category}.memcached.queries
    unicorn.#{category}.memcached.time
    unicorn.#{category}.gitrpc.time
    unicorn.#{category}.es.queries
    unicorn.#{category}.es.time
    unicorn.#{category}.redis.queries
    unicorn.#{category}.redis.time
    unicorn.#{category}.gc.time
    exception.#{data["app"]}.count
    git.hooks.pre_receive.custom.timing
    dgit.#{metric_group}.replicas
    dgit.#{oldmetric_prefix}replica-counts
    dgit.#{metric_group}.non-voting-replicas
    dgit.#{oldmetric_prefix}non-voting-replica-counts
    dgit.3pc.timing
    dgit.all.#{metric}.count
    dgit.#{host}.rpc-error
    #{prefix}.timing
    #{prefix}.up
    #{prefix}.sketchy
    #{prefix}.down
    dgit.maintenance-queries
    dgit.queries.#{stat_method_name}.time
    ldap.sync.new_members.total
    ldap.sync.new_members.runtime
    ldap.sync.team.total
    ldap.sync.team.runtime
    ldap.sync.team_member_search.total
    ldap.sync.team_member_search.runtime
    ldap.sync.teams.total
    ldap.sync.teams.runtime
    ldap.sync.user.total
    ldap.sync.user.runtime
    ldap.sync.users.total
    ldap.sync.users.runtime
    ldap.authenticate.success.runtime
    ldap.authenticate.failure.runtime
    ldap.authenticate.timeout.total
    ldap.search
    ldap.bind
    ldap.team_sync_error
    auth.result.success.web
    auth.result.failure.two_factor.web
    auth.result.#{res}#{auth_failure_key}.#{from}
    public_key.access.count
    integration_client_secret.access.count
    oauth_application_client_secret.access.count
    memcached.error.value-too-big
    memcached.#{hostname}.error.server-evicted
    memcached.#{hostname}.error.retry
    memcached.#{hostname}.error.ignored
    memcached.#{hostname}.error.unexpected
    github_connect_search.timeout
    github_connect_search.error
    github_connect_contributions.timeout
    github_connect_contributions.error
    github_connect_connection.parser
    github_connect_connection.timeout
    github_connect_connection.error
    dotcom_connection.error
    unicorn.#{category}.status_code.#{status_code}.count
    unicorn.#{category}.gc.allocations
    unicorn.#{category}.gc.collections
    unicorn.#{category}.gc.major
    unicorn.#{category}.gc.minor
    unicorn.#{category}.gitrpc.rpcs
    unicorn.#{category}.cache.queries
    unicorn.#{category}.cache.time
    unicorn.#{category}.activerecord.objs
    unicorn.#{category}.memrss
    unicorn.#{category}.requests_per_second
    unicorn.#{category}.response_size
    process_utilization.record_request.duration
    secret_scanning.jobs.#{job_visibility}_#{job_scope}_errors_#{category}
    secret_scanning.jobs.#{job_visibility}_#{job_scope}_latency
  )

  # load core stats stuff
  require "github/stats/counter"
  require "github/stats/api"
  require "github/stats/site"

  def self.site(enterprise = GitHub.enterprise?)
    Site.stats(enterprise)
  end
end
