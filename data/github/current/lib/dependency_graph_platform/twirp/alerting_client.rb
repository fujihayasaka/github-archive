# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  module Twirp
    class AlertingClient < DependencyGraphPlatform::Twirp::BaseClient
      READ_TIMEOUT = 10 # seconds
      DEFAULT_MAX_ATTEMPTS = 10

      class AlertingError < BaseError; end

      ECOSYSTEM_HASH = {
        "npm" => :ECOSYSTEM_NPM,
        "maven" => :ECOSYSTEM_MAVEN,
      }

      sig { params(ecosystem: String, package_name: String, requirements: String, limit: Integer, cursor: T.nilable(T::Hash[Symbol, Integer])).returns(Github::DependencyGraphPlatform::Alerting::V1::AllRepositoriesWithDependencyVersionResponse) }
      def all_repositories_with_dependency_version(ecosystem:, package_name:, requirements:, limit:, cursor: nil)
        twirp_ecosystem = ECOSYSTEM_HASH.fetch(ecosystem, nil)
        if twirp_ecosystem.nil?
          raise ArgumentError.new("ecosystem must be one of #{ECOSYSTEM_HASH.keys}")
        end
        req = {
          package_ecosystem: twirp_ecosystem,
          package_name: package_name,
          requirements: requirements,
          pagination: {
            limit: limit,
          }
        }

        if cursor.present?
          req[:pagination][:cursor] = cursor
        end

        rpc(:AllRepositoriesWithDependencyVersion, req)
      end

      private

      def client_name
        "alerting"
      end

      def twirp_class
        Github::DependencyGraphPlatform::Alerting::V1::AlertingAPIClient
      end
    end
  end
end
