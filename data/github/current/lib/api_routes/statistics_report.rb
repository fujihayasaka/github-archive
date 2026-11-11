# typed: true
# frozen_string_literal: true

class ApiRoutes::StatisticsReport
  NOT_APPLICABLE = [
    "Api::BrowserReporting",
    "Api::Enterprise",
    "Api::Internal",
    "Api::Legacy",
    "Api::Staff",
    "Api::ThirdParty::Mailchimp",
    "Api::Admin", # GHE-only
    "Api::Policies", # Internal API endpoints for creating S3 policies
  ]

  def self.collector
    ApiRoutes::ASTRouteCollector
  end

  attr_reader :skipped_collections, :collections
  def initialize(collections)
    @skipped_collections, @collections = collections.partition do |collection|
      NOT_APPLICABLE.any? do |namespace|
        collection.namespace.start_with?(namespace)
      end
    end
  end

  def print
    skipped_endpoints = skipped_collections.map(&:endpoints).flatten
    endpoints = collections.map(&:endpoints).flatten

    total = endpoints.count
    server_to_server = endpoints.count(&:enabled_for_integrations?)
    user_to_server = endpoints.count(&:enabled_for_user_via_integrations?)
    audited = endpoints.count(&:audited?)
    disabled = endpoints.count(&:disabled?)

    puts <<-TXT
    TOTAL:     #{skipped_endpoints.count + total}
     [ n/a:    #{skipped_endpoints.count} ]
     [ public: #{total} ]

    DISABLED:  #{disabled}

    ENABLED:
     [ installations: #{server_to_server} (remaining: #{total - disabled - server_to_server}) ]
     [ user via apps: #{user_to_server} (remaining: #{total - disabled - user_to_server}) ]

    AUDITED:      #{audited}
     [ remaining: #{total - audited} ]
    TXT
  end
end
