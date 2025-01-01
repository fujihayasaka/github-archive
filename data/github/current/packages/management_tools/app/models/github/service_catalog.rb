# typed: true
# frozen_string_literal: true

require "service-catalog-client"

module GitHub
  class ServiceCatalog
    PRODUCTION_ENDPOINT = "https://catalog.githubapp.com/graphql"
    STAGING_ENDPOINT = "https://catalog-staging.githubapp.com/graphql"

    # By default a lot more is returned so we use a custom fragment here
    # to limit how much we fetch to only what we'll use.
    # See: https://github.com/github/cat/blob/master/service-catalog-client/lib/service-catalog/client/services_query_binder.rb
    SERVICE_NAMES_FRAGMENT = <<-'GRAPHQL'
      fragment ServiceDetail on Service {
        name
      }
    GRAPHQL

    TEAM_NAME_FRAGMENT = <<-'GRAPHQL'
      fragment ServiceDetail on Service {
          team {
            name
          }
        }
    GRAPHQL

    def self.enabled?
      !ENV["SERVICE_CATALOG_TOKEN"].blank?
    end

    def self.client
      @client ||= ::ServiceCatalog::Client.new(
        endpoint: Rails.env.production? ? PRODUCTION_ENDPOINT : STAGING_ENDPOINT,
        token: ENV["SERVICE_CATALOG_TOKEN"],
      )
    end

    def self.find_services_by_name(name:)
      return [] unless enabled?
      client.services.list(filter_selection: { query: name }, service_detail_fragment: SERVICE_NAMES_FRAGMENT).data.services
    end

    # Return service with team name
    #   name: the service slug ie: "github/devtools"
    def self.find_team_by_service(name:)
      return nil unless enabled? && name
      client.services.find(name: name, service_detail_fragment: TEAM_NAME_FRAGMENT).data.service
    end
  end
end
