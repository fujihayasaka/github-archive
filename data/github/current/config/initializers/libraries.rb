# frozen_string_literal: true

# ruby stdlib
require "digest/sha2"
require "digest/sha1"
require "digest/md5"
require "base64"
require "yaml"
require "ostruct"
require "resolv"

# This will be a default gem loaded via gem_prelude.rb in 3.2, once all
# deployments of dotcom are on ruby 3.2 or later we can remove this.
# https://github.com/ruby/ruby/commit/a50df1ab0eb312e5cdcf010d2c1b362ec41f3c59
begin
  require "syntax_suggest/core_ext"
rescue LoadError
  # ignore, this is expected not to exist in non-dev environments.
end

# bring in github lib
require "github"

# bring in all github server connections
require "github/config/actions_runner_ips"
require "github/config/codespaces_vm_ips"
require "github/config/maccloud_ips"
require "github/config/mysql"
require "github/config/memcache"
require "github/config/redis"
require "github/config/kv"
require "github/config/stats"
require "github/config/after_response"
require "github/config/graphite"
require "github/config/munger"

# bring in library configs
require "github/config/context"
require "github/config/s3"
require "github/config/services"
require "github/config/gitrpc"
require "github/config/octocat"
require "github/config/flipper"
require "github/config/dogapi"
require "github/config/presto"
require "github/config/trino"
require "github/config/aqueduct"

# other gems
require "redcloth"
require "version_sorter"
require "will_paginate/array"
require "net/https"
require "color"
require "color_ext"
require "rexml/document"
require "yajl"
require "mustache"
require "oauth2"
require "securerandom"
require "sanitize"
require "addressable/uri"
require "wikicloth"
require "email_reply_parser"
require "sinatra/base"
require "money"
require "money/bank/open_exchange_rates_bank"
require "stratocaster"
require "browser"
# This is also required in lib/github/password.rb
# But until we reference the classes from BCrypt directly
# outside that file, we need to require it globally
require "bcrypt"
require "charlock_holmes"
require "charlock_holmes/string"
require "rinku"
require "rails_rinku"
require "string_ext"
require "time_ext"
require "msgpack_ext"
require "stable_sorter"
require "elastomer"
require "premailer"
require "simple_uuid"
require "rqrcode"
require "prawn"
require "prawn-svg"
require "twilio-ruby"
require "geoip2_compat"
require "octolytics"
require "prose_diff"
require "will_paginate"
require "diff/lcs"
require "github-pages-health-check"
require "coconductor"
require "licensee"
require "coconductor"
require "phonelib"
require "lru_redux"
require "secure_headers"
require "octicons_helper"
require "commonmarker"
require "acme-client"
require "hydro"
require "hydro/protobuf/invalid_enum_value_error"
require "public_suffix"
require "homograph_detector"
require "webauthn"
require "aqueduct"
require "ssh_data"
require "ed25519"
require "driftwood/v1/client"
require "codeowners"
require "meuse/client"
require "billing-platform"
require "actions-usage-metrics"
require "s4/v1/client"
require "azure/storage/blob"
require "kusto/data"
require "mvnd"

# github libs
require "acme_client"
require "active_record/column_types/compressed_binary"
require "active_record/column_types/compressed_integer_array"
require "active_record/column_types/compressed_string"
require "active_record/column_types/packed_integer_array"
require "active_record/column_types/string_from_binary"
require "active_record/column_types/unconverted_string_from_binary"
require "github/egress"
require "github/packers"
require "github/job_stats"
require "github/jobs/facts_from_survey_answers"
require "linguist"
require "github/markup"
require "api_routes"
require "apps"
require "arvore"
require "authorization/content_authorizer"
require "base62"
require "classroom"
require "conduit"
require "cpu_timer"
require "database_selector"
require "dependabot"
require "dependency_graph"
require "dependency_review"
require "dependency_snapshot"
require "dependency_graph_platform"
require "diff_entry_highlighting"
require "diff_entry_suggested_change"
require "diff_generator"
require "dsr"
require "education"
require "elastomer/query_stats"
require "eloqua"
require "events"
require "event_trace"
require "explore_feed"
require "fastly"
require "marketing_forms"
require "gh"
require "git_auth"
require "google_analytics"
require "hydro_loader"
require "instrumentation"
require "launch"
require "newsies"
require "open_graph"
require "redis_rate_limiter/redis_rate_limiter"
require "redis_rate_limiter/result"
require "redis_rate_limiter/api_redis_rate_limiter"
require "scientist"
require "scim"
require "search"
require "spokes_api"
require "task_list"
require "trace_renderer/datadog_client"
require "trace_renderer/mermaid_trace"
require "timer"
require "git_signing"
require "gitkeeper"
require "gpg_verify"
require "pgp_armor"
require "authorization"
require "instrumentation/model"
require "dumpable"
require "global_instrumenter"
require "github/html_safe_string"
require "actions"
require "audit/context"
require "audit/operation_types"
require "workflow"
require "zendesk"
require "scout"
require "prelude"
require "pond"
require "azure_exp"
require "cruby_crash_info"
require "two_factor_requirement"
require "feature_management"
require "actions_results"
require "github/progress"
require "actions_broker"
require "actions_broker_worker"
require "actions_metrics"
require "actions_runner_admin"
require "actions_run_service"
require "regex/re2_helper"
require "states_and_province_helper"
require "mobile"
require "hosted_compute_ims"
require "copilot_limiter"

# github rack overrides
require "rack/request_id"
require "rack/request_logger"
require "rack/server_id"
require "promise"

# Disable nagle on excon connections.
# Currently these are used by the gpgverify and search client libraries.
require "excon"
Excon.defaults[:tcp_nodelay] = true

# faraday adapter to allow concurrent requests
require "concurrent_faraday"

# charliesome's favorite module
require "active_support/concern"

# Don't parse JSON requests by default.  See #21699
ActionDispatch::Request.parameter_parsers.delete Mime[:json].symbol

# platform and graphql
require "graphql/client"

ActiveSupport::XmlMini.backend = "Nokogiri"

require "last_modified_calculation"
ActiveRecord::Base.send :include, LastModifiedCalculation

require "github/active_record_enumerable_protection"
GitHub::ActiveRecordEnumerableProtection.initialize
require "github/active_record_readonly_mode"
GitHub::ActiveRecordReadonlyMode.initialize

begin
  require "rblineprof"
  require "stackprof"
  require "vernier"
rescue LoadError
  # it's not the end of the world if we can't load up some profilers
end
