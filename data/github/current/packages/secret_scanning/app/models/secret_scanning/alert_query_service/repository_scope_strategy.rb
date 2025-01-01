# typed: true
# frozen_string_literal: true

module SecretScanning
  class AlertQueryService

    class RepositoryScopeStrategy < ScopeStrategy
      include SecretScanning::Features::FeatureFlagHelper

      attr_reader :repository, :parsed_query

      def initialize(repository:, parsed_query:)
        raise ArgumentError, "Must provide a Repository" unless repository.instance_of?(Repository)
        raise ArgumentError, "Must provide a SecretScanningQuery" unless parsed_query.instance_of?(Search::Queries::SecurityCenter::SecretScanningQuery)

        @repository = repository
        @parsed_query = parsed_query
      end

      ##
      # @see ScopeStrategy#with_selector!
      def with_selector!(request_hash, aggregation_filter: nil)
        request_hash[:repo_selector] = GitHub::Proto::SecretScanning::Api::V2::RepoSelector.new(
          repository_id: repository.id
        )
      end

      ##
      # @see ScopeStrategy#with_feature_flags!
      def with_feature_flags!(request_hash)
        request_hash[:feature_flags].concat get_tokens_api_feature_flags(repository)
      end

      ##
      # @see ScopeStrategy#tenant_filter_scope
      def tenant_filter_scope
        GitHub::SecurityCenter::TenantFilteringHelper::RequestScope.new(:repository, repository, "secret_scanning")
      end

      ##
      # @see ScopeStrategy#show_custom_patterns?
      def show_custom_patterns?
        SecretScanning::Features::Repo::CustomPatterns.new(repository).feature_available?
      end
    end

  end
end
