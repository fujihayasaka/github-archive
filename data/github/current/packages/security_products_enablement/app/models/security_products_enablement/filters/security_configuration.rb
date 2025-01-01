# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  module Filters
    class SecurityConfiguration

      include GitHub::Memoizer
      include Settings::SecurityProducts::AuditLogHelper

      NO_CONFIG_KEYWORD = "None"

      CONFIGURATION_NAME_FILTER = "configuration"
      CONFIGURATION_STATUS_FILTER = "config-status"
      FAILURE_REASON_FILTER = "failure-reason"

      NEGATED_CONFIGURATION_NAME_FILTER = "-configuration"
      NEGATED_CONFIGURATION_STATUS_FILTER = "-config-status"
      NEGATED_FAILURE_REASON_FILTER = "-failure-reason"

      CONFIGURATION_NAME_FILTERS = [CONFIGURATION_NAME_FILTER, NEGATED_CONFIGURATION_NAME_FILTER]
      CONFIGURATION_STATUS_FILTERS = [CONFIGURATION_STATUS_FILTER, NEGATED_CONFIGURATION_STATUS_FILTER]
      FAILURE_REASON_FILTERS = [FAILURE_REASON_FILTER, NEGATED_FAILURE_REASON_FILTER]

      # This is a map of the filter token values to an array of the verbose failure reasons that are stored in the database.
      # Ex. The map looks like this { "filter_token": ["failure reason", "another failure reason"], ... }
      FAILURE_REASON_TOKEN_MAP = ENABLEMENT_FAILURES_MAP.group_by { |_, v| v["filter_token"] }.transform_values do |values|
        values.flatten!.select! { |v| v.is_a? String }
      end.merge(
        # These reasons match errors that might get raised within ApplySecurityConfigurationToRepositoryJob
        # since they will get persisted to the database and displayed as "Unknown" in the front-end:
        "unknown" => [
          nil,
          "error",
          "retryable_error",
          "fatal_error",
          "repository_not_found",
          "actor_not_found",
          "security_configuration_not_found",
          "repository_security_configuration_not_found",
          "security_configuration_owner_mismatch"
        ]
      )

      sig { params(org: Organization, user: User, filter_hash: T::Hash[String, T.untyped]).void }
      def initialize(org, user, filter_hash)
        @org = org
        @user = user
        @filter_hash = filter_hash
      end

      sig { returns(T::Array[Integer]) }
      def apply
        return [] unless configuration_filters_present?

        # When the query filters for repos that do not have any config and match a config status
        # (config-name:"No configuration" config-status:attached), return an empty array.
        # This is because a repo cannot have a config status if it does not have a config.
        return [] if @filter_hash["config-status"].present? && filter_for_repos_without_configs? && config_names.blank?

        GitHub.dogstats.distribution_time("security_products_enablement.filters.security_configuration") do
          scope = RepositorySecurityConfiguration.where(organization_id: @org.id)

          # This block will handle config-status queries their negations:
          # 1. config-status:attached
          # 2. -config-status:detached
          if filter_key = fetch_configuration_status_filter
            # "enforced" configs are a subset of "attached" configs,
            # so we include "enforced" configs when filtering for "attached" configs
            if @filter_hash[filter_key].include?("attached")
              @filter_hash[filter_key] << "enforced"
            end

            scope = if filter_key == CONFIGURATION_STATUS_FILTER
              scope.where(state: @filter_hash[filter_key])
            else
              scope.where.not(state: @filter_hash[filter_key])
            end
          end

          # This block will handle configuration name queries and their negations:
          # 1. config-name:"My config"
          # 2. config-name:"My config",None
          # 3. -config-name:None
          scope = if fetch_configuration_name_filter == CONFIGURATION_NAME_FILTER
            scope.where(security_configuration_id: find_security_config_ids_by_names)
          else
            scope.where.not(security_configuration_id: find_security_config_ids_by_names)
          end

          # This block handles the failure reason filter and its negation:
          # 1. failure-reason:actions_disabled
          # 2. -failure-reason:licenses
          if failure_reason_filter = fetch_failure_reason_filter
            failure_reasons_to_query = []

            @filter_hash[failure_reason_filter].each do |failure_reason_query|
              # Since we simplify failure reasons in the UI, we need to map the input to their verbose counterparts:
              failure_reasons_to_query << FAILURE_REASON_TOKEN_MAP[failure_reason_query]
            end
            failure_reasons_to_query.flatten!

            scope = if failure_reason_filter == FAILURE_REASON_FILTER
              scope.where(state: "failed", failure_reason: failure_reasons_to_query)
            else
              # Exclude any known failure reasons passed in the query:
              tmp_scope = scope.where.not(failure_reason: failure_reasons_to_query)

              if @filter_hash[failure_reason_filter].include?("unknown")
                # User is excluding unknown failure reasons, we need to find failed records WHERE reason is not NULL:
                tmp_scope.where(state: "failed").where.not(failure_reason: nil)
              else
                # User is excluding known failure reasons, we need to find failed records WHERE reason IS NULL:
                tmp_scope.or(scope.where(state: "failed", failure_reason: nil))
              end
            end
          end

          repo_ids = scope.pluck(:repository_id)
          # We add on the repo IDs if the query includes configuration:None and does not have a config-status filter
          # Ex., In this query: "config-status:attached configuration:None" we don't need to look for repos that don't
          # have a config because these repos will be removed when matched with the config-status filter.
          # If the query includes exlicit configurations and None, we need to check on unique repo IDs to avoid duplicates.
          filter_for_repos_without_configs? ? (repo_ids + repo_ids_without_configs).uniq : repo_ids
        end
      end

      sig { returns(T::Boolean) }
      def can_apply?
        configuration_filters_present?
      end

      private

      sig { returns(T.nilable(String)) }
      memoize def fetch_configuration_status_filter
        CONFIGURATION_STATUS_FILTERS.find { |filter| @filter_hash.key?(filter) }
      end

      sig { returns(T.nilable(String)) }
      memoize def fetch_configuration_name_filter
        CONFIGURATION_NAME_FILTERS.find { |filter| @filter_hash.key?(filter) }
      end

      sig { returns(T.nilable(String)) }
      memoize def fetch_failure_reason_filter
        FAILURE_REASON_FILTERS.find { |filter| @filter_hash.key?(filter) }
      end

      sig { returns(T::Boolean) }
      memoize def configuration_filters_present?
        (CONFIGURATION_NAME_FILTERS + CONFIGURATION_STATUS_FILTERS + FAILURE_REASON_FILTERS).any? { |filter| @filter_hash.key?(filter) }
      end

      sig { returns(T::Array[String]) }
      memoize def config_names
        key = CONFIGURATION_NAME_FILTERS.find { |filter| @filter_hash.key?(filter) }
        return [] unless key

        @filter_hash[key].select { |n| n != NO_CONFIG_KEYWORD }
      end

      sig { returns(T::Boolean) }
      def filter_for_repos_without_configs?
        !fetch_configuration_status_filter && @filter_hash.fetch(CONFIGURATION_NAME_FILTER, []).include?(NO_CONFIG_KEYWORD)
      end

      sig { returns(T::Array[Integer]) }
      def find_security_config_ids_by_names
        config_ids = ::SecurityConfiguration.where(target: @org, name: config_names).pluck(:id)

        if ::SecurityConfiguration.github_recommended_configuration && config_names.any? { |name| name.upcase == ::SecurityConfiguration::GH_CONFIG_NAME.upcase }
          config_ids << ::SecurityConfiguration.github_recommended_configuration&.id
        end

        if @org.business.present?
          ::SecurityConfiguration.where(target: @org.business, name: config_names).pluck(:id).each do |id|
            config_ids << id unless config_ids.include?(id)
          end
        end

        config_ids
      end

      sig { returns(T::Array[Integer]) }
      def repo_ids_without_configs
        results = T.let([], T::Array[Integer])
        repos_with_configs = RepositorySecurityConfiguration.where(organization_id: @org.id).applied_or_attaching.pluck(:repository_id)
        repos_scope = @org.visible_repositories_for(@user)

        repos_scope.in_batches(of: 1000) do |repos|
          results += (repos.pluck(:id) - repos_with_configs)
        end

        results
      end
    end
  end
end
