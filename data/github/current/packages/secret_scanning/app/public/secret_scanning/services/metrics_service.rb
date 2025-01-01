# typed: strict
# frozen_string_literal: true

module SecretScanning
  module Services
    class MetricsService
      extend T::Sig

      class RepoOwnerType < T::Enum
        enums do
          Any = new
          Organization = new
          User = new
        end
      end

      class RepoOwnersFilters < T::Struct
        prop :owner_type, RepoOwnerType, default: RepoOwnerType::Any
        prop :org_ids, T.nilable(T::Array[Integer])
        prop :exclude_org_ids, T.nilable(T::Array[Integer])
        prop :user_ids, T.nilable(T::Array[Integer])
        prop :exclude_user_ids, T.nilable(T::Array[Integer])
      end

      class PushProtectionTokenFilters < T::Struct
        extend T::Sig

        prop :token_types, T::Array[String], default: []
        prop :exclude_token_types, T::Array[String], default: []
        prop :token_providers, T::Array[String], default: []
        prop :exclude_token_providers, T::Array[String], default: []
        prop :token_validities, T::Array[Integer], default: []
        prop :exclude_token_validities, T::Array[Integer], default: []

        sig { returns(T::Hash[String, T.untyped]) }
        def serialize
          super.tap do |h|
            h = h.with_indifferent_access
          end
        end
      end

      sig do
        params(
          token_type: String,
          owner: T.any(Repository, Organization, Business),
          actor: User
        ).returns(T.nilable(SecretScanning::Models::TokenPushProtectionMetrics))
      end
      def self.get_token_push_protection_metrics(token_type, owner, actor)
        request = {
          owner_id: owner.id,
          owner_scope: self.to_proto_owner_scope(owner),
          token_type: token_type,
        }

        response = GitHub::TokenScanning::Service::Client.new(actor).get_token_push_protection_metrics(request)

        if response.nil? || response.error || response.data.nil?
          return nil
        end

        SecretScanning::Models::TokenPushProtectionMetrics.new(
          total_block_count: response.data.total_blocks,
          successful_block_count: response.data.successful_blocks,
          bypassed_alert_count: response.data.bypassed_alerts
        )
      end

      sig do
        params(
          scope: T.any(::Organization, ::Business),
          actor: User,
          repo_ids: T.nilable(T::Array[Integer]),
          exclude_repo_ids: T.nilable(T::Array[Integer]),
          repo_owners: T.nilable(RepoOwnersFilters),
          repos_in_archived_state: T.nilable(T::Boolean),
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          token_filters: T.nilable(PushProtectionTokenFilters)
        ).returns([T.nilable(SecretScanning::Models::PushProtectionMetrics), T.any(T::Boolean, StandardError, Twirp::Error)])
      end
      def self.get_push_protection_metrics(scope, actor, repo_ids: [], exclude_repo_ids: [], repo_owners: nil, repos_in_archived_state: nil, start_date: nil, end_date: nil, token_filters: nil)
        request = {
          owner_id: scope.id,
          owner_scope: self.to_proto_owner_scope(scope),
          repo_ids:,
          exclude_repo_ids:,
          repo_archived_state: to_proto_repo_archived_state(repos_in_archived_state)
        }

        if token_filters
          request[:token_types] = token_filters.token_types
          request[:exclude_token_types] = token_filters.exclude_token_types
          request[:token_providers] = token_filters.token_providers
          request[:exclude_token_providers] = token_filters.exclude_token_providers
          request[:token_validities] = token_filters.token_validities
          request[:exclude_token_validities] = token_filters.exclude_token_validities
        end

        request[:repo_owners] = to_proto_repo_owners(repo_owners) if repo_owners

        if start_date.present?
          request[:start_date] = Google::Protobuf::Timestamp.new
          request[:start_date].seconds = start_date.to_time.to_i
        end

        if end_date.present?
          request[:end_date] = Google::Protobuf::Timestamp.new
          request[:end_date].seconds = end_date.to_time.to_i
        end

        response = GitHub::TokenScanning::Service::Client.new(actor).get_push_protection_metrics(request)

        if response.nil?
          GitHub.dogstats.increment("secret_scanning_metrics.get_push_protection_metrics.no-response")
          return [nil, true]
        end

        if response.error
          GitHub.dogstats.increment("secret_scanning_metrics.get_push_protection_metrics.error")
          return [nil, response.error]
        end

        if response&.data.nil?
          GitHub.dogstats.increment("secret_scanning_metrics.get_push_protection_metrics.empty-payload")
          return [nil, true]
        end

        # For repo counts, we need to fetch additional information about Repositories, but let's only run a single query
        repo_ids_for_query = Set.new
        repos_by_id = T::let({}, T::Hash[Integer, Repository])

        blocks_by_repository_counts = []
        response.data.blocks_by_repository_counts.to_a.each do |proto|
          metric = SecretScanning::Models::RepoCountMetric.from_proto(proto)
          blocks_by_repository_counts.push(metric)
          repo_ids_for_query.add(metric.repo_id)
        end

        bypasses_by_repository_counts = []
        response.data.bypasses_by_repository_counts.to_a.each do |proto|
          metric = SecretScanning::Models::RepoCountMetric.from_proto(proto)
          bypasses_by_repository_counts.push(metric)
          repo_ids_for_query.add(metric.repo_id)
        end

        Repository.where(id: repo_ids_for_query.to_a).each { |repo| repos_by_id[repo.id] = repo }

        # populate additional repo fields and filter out repos we can't find
        # we also filter out any deleted repos that may have not been synced yet
        blocks_by_repository_counts = blocks_by_repository_counts.filter_map do |metric|
          if repos_by_id.has_key?(metric.repo_id)
            repo = T.must(repos_by_id[metric.repo_id])
            metric.repo_name = scope.is_a?(Business) ? repo.name_with_display_owner : repo.name

            metric if !repo.deleted?
          end
        end

        bypasses_by_repository_counts = bypasses_by_repository_counts.filter_map do |metric|
          if repos_by_id.has_key?(metric.repo_id)
            repo = T.must(repos_by_id[metric.repo_id])
            metric.repo_name = scope.is_a?(Business) ? repo.name_with_display_owner : repo.name

            metric if !repo.deleted?
          end
        end

        bypasses_by_reason_counts = response.data.bypasses_by_reason_counts.to_a.map { |metric| SecretScanning::Models::BypassReasonCountMetric.from_proto(metric) }
        bypasses_sum = bypasses_by_reason_counts.sum(&:count)

        if bypasses_sum > 0
          bypasses_by_reason_counts.each { |metric| metric.percent = (metric.count.to_f / bypasses_sum.to_f * 100).round }
        end

        bypass_requests_count, mean_response_time, bypasses_by_request_status_counts = get_delegated_bypass_metrics(
          scope,
          actor,
          repo_ids: repo_ids.to_a,
          exclude_repo_ids: exclude_repo_ids,
          repo_owners: repo_owners,
          repos_in_archived_state: repos_in_archived_state,
          start_date: start_date,
          end_date: end_date,
          token_filters: token_filters,
          bypass_request_ids: response.data.bypass_request_ids.to_a,
        )

        [SecretScanning::Models::PushProtectionMetrics.new(
          total_block_count: response.data.total_blocks_count,
          successful_block_count: response.data.successful_blocks_count,
          bypassed_alert_count: response.data.bypassed_alerts_count,
          bypass_requests_count: bypass_requests_count,
          mean_response_time: mean_response_time.round,
          blocks_by_token_type_counts: response.data.blocks_by_token_type_counts.to_a.map { |metric| SecretScanning::Models::TokenTypeCountMetric.from_proto(metric) },
          blocks_by_repository_counts: blocks_by_repository_counts,
          bypasses_by_token_type_counts: response.data.bypasses_by_token_type_counts.to_a.map { |metric| SecretScanning::Models::TokenTypeCountMetric.from_proto(metric) },
          bypasses_by_repository_counts: bypasses_by_repository_counts,
          bypasses_by_reason_counts: bypasses_by_reason_counts,
          bypasses_by_request_status_counts: bypasses_by_request_status_counts,
        ), false]
      end

      sig do
        params(
          scope: T.any(::Organization, ::Business),
          actor: User,
          repo_ids: T.nilable(T::Array[Integer]),
          exclude_repo_ids: T.nilable(T::Array[Integer]),
          repo_owners: T.nilable(RepoOwnersFilters),
          repos_in_archived_state: T.nilable(T::Boolean),
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          token_filters: T.nilable(PushProtectionTokenFilters),
          bypass_request_ids: T.nilable(T::Array[Integer]),
        ).returns([
          Integer,
          Integer,
          T::Array[SecretScanning::Models::BypassRequestStatusCountMetric],
        ])
      end
      def self.get_delegated_bypass_metrics(scope, actor, repo_ids: [], exclude_repo_ids: [], repo_owners: nil, repos_in_archived_state: nil, start_date: nil, end_date: nil, token_filters: nil, bypass_request_ids: [])
        bypass_requests = Exemptions::ExemptionRequest.not_expired.where(request_type: SecretScanning::Constants::EXEMPTION_REQUEST_TYPE)

        if scope.is_a?(Business)
          owner_ids = []
          scope.organizations.in_batches { |org| owner_ids.concat(org.pluck(:id)) }
          if SecurityProduct::Permissions::BusinessAuthz.new(scope, actor: actor).can_view_user_owned_repository_alerts?
            ::SecurityOverviewAnalytics::Repository.where(business_id: scope.id, owner_type: "USER").in_batches { |config| owner_ids.concat(config.pluck(:owner_id)) }
          end
          bypass_requests = bypass_requests.joins(:repository).where(repository: { owner_id: owner_ids })
        else
          bypass_requests = bypass_requests.joins(:repository).where(repository: { owner_id: scope.id })
        end

        bypass_requests = bypass_requests.where(repository_id: repo_ids) unless repo_ids.nil? || repo_ids.empty?

        exclude_repo_ids = exclude_repo_ids || []
        if repo_owners
          owner_repo_ids = []
          if repo_owners.owner_type != RepoOwnerType::User
            owner_repo_ids.concat(::SecurityOverviewAnalytics::Repository.where(business_id: scope.id, owner_type: "ORGANIZATION", owner_id: repo_owners.org_ids).pluck(:repository_id)) if repo_owners.org_ids
            exclude_repo_ids.concat(::SecurityOverviewAnalytics::Repository.where(business_id: scope.id, owner_type: "ORGANIZATION", owner_id: repo_owners.exclude_org_ids).pluck(:repository_id)) if repo_owners.exclude_org_ids
          end

          if repo_owners.owner_type != RepoOwnerType::Organization
            owner_repo_ids.concat(::SecurityOverviewAnalytics::Repository.where(business_id: scope.id, owner_type: "USER", owner_id: repo_owners.user_ids).pluck(:repository_id)) if repo_owners.user_ids
            exclude_repo_ids.concat(::SecurityOverviewAnalytics::Repository.where(business_id: scope.id, owner_type: "USER", owner_id: repo_owners.exclude_user_ids).pluck(:repository_id)) if repo_owners.exclude_user_ids
          end
          bypass_requests = bypass_requests.where(repository_id: owner_repo_ids)
        end

        bypass_requests = bypass_requests.where.not(repository_id: exclude_repo_ids) unless exclude_repo_ids.empty?

        unless repos_in_archived_state.nil?
          if repos_in_archived_state
            bypass_requests = bypass_requests.joins(:repository).where.not(repository: { archived_at: nil })
          else
            bypass_requests = bypass_requests.joins(:repository).where(repository: { archived_at: nil })
          end
        end

        bypass_requests = bypass_requests.where(created_at: start_date.beginning_of_day..) unless start_date.nil?
        bypass_requests = bypass_requests.where(created_at: ..end_date.end_of_day) unless end_date.nil?

        bypass_requests = bypass_requests.where(id: bypass_request_ids) if token_filters

        bypass_requests_count = Integer(bypass_requests.count)

        total_response_time = 0
        response_count = 0
        approved_count = 0
        rejected_count = 0
        cancelled_count = 0
        pending_count = 0
        bypass_requests.each do |bypass_request|
          bypass_response = bypass_request.responses.order(:created_at).first
          if bypass_response
            if bypass_response.status == "approved"
              approved_count += 1
            elsif bypass_response.status == "rejected"
              rejected_count += 1
            end
            total_response_time += bypass_response.created_at - bypass_request.created_at
            response_count += 1
          else
            if bypass_request.status == "cancelled"
              cancelled_count += 1
            elsif bypass_request.status == "pending"
              pending_count += 1
            end
          end
        end

        mean_response_time = Integer(response_count > 0 ? total_response_time / response_count : 0)

        bypasses_by_request_status_counts = []
        bypasses_by_request_status_counts.push(SecretScanning::Models::BypassRequestStatusCountMetric.new(count: approved_count, percent: (approved_count.to_f / bypass_requests_count * 100).round, bypass_request_status: :approved)) if approved_count > 0
        bypasses_by_request_status_counts.push(SecretScanning::Models::BypassRequestStatusCountMetric.new(count: rejected_count, percent: (rejected_count.to_f / bypass_requests_count * 100).round, bypass_request_status: :rejected)) if rejected_count > 0
        bypasses_by_request_status_counts.push(SecretScanning::Models::BypassRequestStatusCountMetric.new(count: cancelled_count, percent: (cancelled_count.to_f / bypass_requests_count * 100).round, bypass_request_status: :cancelled)) if cancelled_count > 0
        bypasses_by_request_status_counts.push(SecretScanning::Models::BypassRequestStatusCountMetric.new(count: pending_count, percent: (pending_count.to_f / bypass_requests_count * 100).round, bypass_request_status: :pending)) if pending_count > 0

        [bypass_requests_count, mean_response_time, bypasses_by_request_status_counts]
      end

      sig do
        params(
          scope: T.any(::Organization, ::Business),
          actor: User,
          repo_ids: T.nilable(T::Array[Integer]),
          exclude_repo_ids: T.nilable(T::Array[Integer]),
          repo_owners: T.nilable(RepoOwnersFilters),
          repos_in_archived_state: T.nilable(T::Boolean),
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          token_filters: T.nilable(PushProtectionTokenFilters)
        ).returns([T.nilable(SecretScanning::Models::PushProtectionMetricsForRepos), T.any(T::Boolean, StandardError)])
      end
      def self.get_push_protection_metrics_for_repos(scope, actor, repo_ids: [], exclude_repo_ids: [], repo_owners: nil, repos_in_archived_state: nil, start_date: nil, end_date: nil, token_filters: nil)
        request = {
          owner_id: scope.id,
          owner_scope: self.to_proto_owner_scope(scope),
          repo_ids:,
          exclude_repo_ids:,
          repo_archived_state: to_proto_repo_archived_state(repos_in_archived_state)
        }

        if token_filters
          request[:token_types] = token_filters.token_types
          request[:exclude_token_types] = token_filters.exclude_token_types
          request[:token_providers] = token_filters.token_providers
          request[:exclude_token_providers] = token_filters.exclude_token_providers
          request[:token_validities] = token_filters.token_validities
          request[:exclude_token_validities] = token_filters.exclude_token_validities
        end

        request[:repo_owners] = to_proto_repo_owners(repo_owners) if repo_owners

        if start_date.present?
          request[:start_date] = Google::Protobuf::Timestamp.new
          request[:start_date].seconds = start_date.to_time.to_i
        end

        if end_date.present?
          request[:end_date] = Google::Protobuf::Timestamp.new
          request[:end_date].seconds = end_date.to_time.to_i
        end

        response = GitHub::TokenScanning::Service::Client.new(actor).get_push_protection_metrics_for_repos(request)

        if response.nil?
          GitHub.dogstats.increment("security_overview_analytics.dashboards.overview.secrets_blocked.get_push_protection_metrics_for_repos.no-response")
          return [nil, true]
        end

        if response.error
          GitHub.dogstats.increment("security_overview_analytics.dashboards.overview.secrets_blocked.get_push_protection_metrics_for_repos.error")
          return [nil, response.error]
        end

        if response&.data.nil?
          GitHub.dogstats.increment("security_overview_analytics.dashboards.overview.secrets_blocked.get_push_protection_metrics_for_repos.no-data")
          return [nil, false]
        end

        [
          SecretScanning::Models::PushProtectionMetricsForRepos.new(
            total_block_count: response.data.total_blocks_count,
            successful_block_count: response.data.successful_blocks_count,
            bypassed_alert_count: response.data.bypassed_alerts_count,
          ),
          false
        ]
      end

      sig do
        params(
          token_type: String,
          owner: T.any(Repository, Organization, Business),
          actor: User
        ).returns(T.nilable(SecretScanning::Models::TokenAlertMetrics))
      end
      def self.get_token_alert_metrics(token_type, owner, actor)
        request = {
          owner_id: owner.id,
          owner_scope: self.to_proto_owner_scope(owner),
          token_type: token_type,
        }

        response = GitHub::TokenScanning::Service::Client.new(actor).get_token_alert_metrics(request)

        if response.nil? || response.error || response.data.nil?
          return nil
        end

        SecretScanning::Models::TokenAlertMetrics.new(
          open_alert_count: response.data.open_alerts,
          closed_alert_count: response.data.closed_alerts,
          false_positive_count: response.data.false_positive_alerts,
        )
      end

      sig do
        params(
          scope: T.any(::Organization, ::Business),
          actor: User,
          cursor: T.nilable(String),
          repo_ids: T.nilable(T::Array[Integer]),
          exclude_repo_ids: T.nilable(T::Array[Integer]),
          repo_owners: T.nilable(RepoOwnersFilters),
          repos_in_archived_state: T.nilable(T::Boolean),
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          token_filters: T.nilable(PushProtectionTokenFilters)
        ).returns(T.nilable(SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]]))
      end
      def self.get_block_counts_by_token_type(scope, actor, cursor = nil, repo_ids: [], exclude_repo_ids: [], repo_owners: nil, repos_in_archived_state: nil, start_date: nil, end_date: nil, token_filters: nil)
        request = {
          owner_id: scope.id,
          owner_scope: self.to_proto_owner_scope(scope),
          cursor: cursor,
          repo_ids:,
          exclude_repo_ids:,
          repo_archived_state: to_proto_repo_archived_state(repos_in_archived_state)
        }

        if token_filters
          request[:token_types] = token_filters.token_types
          request[:exclude_token_types] = token_filters.exclude_token_types
          request[:token_providers] = token_filters.token_providers
          request[:exclude_token_providers] = token_filters.exclude_token_providers
        end

        request[:repo_owners] = to_proto_repo_owners(repo_owners) if repo_owners

        if start_date.present?
          request[:start_date] = Google::Protobuf::Timestamp.new
          request[:start_date].seconds = start_date.to_time.to_i
        end

        if end_date.present?
          request[:end_date] = Google::Protobuf::Timestamp.new
          request[:end_date].seconds = end_date.to_time.to_i
        end

        response = GitHub::TokenScanning::Service::Client.new(actor).get_block_counts_by_token_type(request)

        if response.nil? || response.error || response.data.nil?
          return nil
        end

        SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]].new(
          data: response.data.counts.map { |metric| SecretScanning::Models::TokenTypeCountMetric.from_proto(metric) },
          next_cursor: response.data.next_cursor,
          previous_cursor: response.data.previous_cursor,
        )
      end

      sig do
        params(
          scope: T.any(::Organization, ::Business),
          actor: User,
          cursor: T.nilable(String),
          repo_ids: T.nilable(T::Array[Integer]),
          exclude_repo_ids: T.nilable(T::Array[Integer]),
          repo_owners: T.nilable(RepoOwnersFilters),
          repos_in_archived_state: T.nilable(T::Boolean),
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          token_filters: T.nilable(PushProtectionTokenFilters)
        ).returns(T.nilable(SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]]))
      end
      def self.get_block_counts_by_repo(scope, actor, cursor = nil, repo_ids: [], exclude_repo_ids: [], repo_owners: nil, repos_in_archived_state: nil, start_date: nil, end_date: nil, token_filters: nil)
        request = {
          owner_id: scope.id,
          owner_scope: self.to_proto_owner_scope(scope),
          cursor: cursor,
          repo_ids:,
          exclude_repo_ids:,
          repo_archived_state: to_proto_repo_archived_state(repos_in_archived_state)
        }

        if token_filters
          request[:token_types] = token_filters.token_types
          request[:exclude_token_types] = token_filters.exclude_token_types
          request[:token_providers] = token_filters.token_providers
          request[:exclude_token_providers] = token_filters.exclude_token_providers
        end

        request[:repo_owners] = to_proto_repo_owners(repo_owners) if repo_owners

        if start_date.present?
          request[:start_date] = Google::Protobuf::Timestamp.new
          request[:start_date].seconds = start_date.to_time.to_i
        end

        if end_date.present?
          request[:end_date] = Google::Protobuf::Timestamp.new
          request[:end_date].seconds = end_date.to_time.to_i
        end

        response = GitHub::TokenScanning::Service::Client.new(actor).get_block_counts_by_repo(request)

        if response.nil? || response.error || response.data.nil?
          return nil
        end

        repo_ids = Set.new
        repos_by_id = T::let({}, T::Hash[Integer, Repository])
        blocks_by_repository_counts = T.let([], T::Array[SecretScanning::Models::RepoCountMetric])

        response.data.counts.each do |proto|
          metric = SecretScanning::Models::RepoCountMetric.from_proto(proto)
          blocks_by_repository_counts.push(metric)
          repo_ids.add(metric.repo_id)
        end

        Repository.where(id: repo_ids.to_a).each { |repo| repos_by_id[repo.id] = repo }

        # populate additional repo fields and filter out repos we can't find
        # we also filter out any deleted repos that may have not been synced yet
        data = blocks_by_repository_counts.filter_map do |metric|
          if repos_by_id.has_key?(metric.repo_id)
            repo = T.must(repos_by_id[metric.repo_id])
            metric.repo_name = scope.is_a?(Business) ? repo.name_with_display_owner : repo.name

            metric if !repo.deleted?
          end
        end

        SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]].new(
          data: data,
          next_cursor: response.data.next_cursor,
          previous_cursor: response.data.previous_cursor,
        )
      end

      sig do
        params(
          scope: T.any(::Organization, ::Business),
          actor: User,
          cursor: T.nilable(String),
          repo_ids: T.nilable(T::Array[Integer]),
          exclude_repo_ids: T.nilable(T::Array[Integer]),
          repo_owners: T.nilable(RepoOwnersFilters),
          repos_in_archived_state: T.nilable(T::Boolean),
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          token_filters: T.nilable(PushProtectionTokenFilters)
        ).returns(T.nilable(SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]]))
      end
      def self.get_bypass_counts_by_token_type(scope, actor, cursor = nil, repo_ids: [], exclude_repo_ids: [], repo_owners: nil, repos_in_archived_state: nil, start_date: nil, end_date: nil, token_filters: nil)
        request = {
          owner_id: scope.id,
          owner_scope: self.to_proto_owner_scope(scope),
          cursor: cursor,
          repo_ids:,
          exclude_repo_ids:,
          repo_archived_state: to_proto_repo_archived_state(repos_in_archived_state)
        }

        if token_filters
          request[:token_types] = token_filters.token_types
          request[:exclude_token_types] = token_filters.exclude_token_types
          request[:token_providers] = token_filters.token_providers
          request[:exclude_token_providers] = token_filters.exclude_token_providers
          request[:token_validities] = token_filters.token_validities
          request[:exclude_token_validities] = token_filters.exclude_token_validities
        end

        request[:repo_owners] = to_proto_repo_owners(repo_owners) if repo_owners

        if start_date.present?
          request[:start_date] = Google::Protobuf::Timestamp.new
          request[:start_date].seconds = start_date.to_time.to_i
        end

        if end_date.present?
          request[:end_date] = Google::Protobuf::Timestamp.new
          request[:end_date].seconds = end_date.to_time.to_i
        end

        response = GitHub::TokenScanning::Service::Client.new(actor).get_bypass_counts_by_token_type(request)

        if response.nil? || response.error || response.data.nil?
          return nil
        end

        SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]].new(
          data: response.data.counts.map { |metric| SecretScanning::Models::TokenTypeCountMetric.from_proto(metric) },
          next_cursor: response.data.next_cursor,
          previous_cursor: response.data.previous_cursor,
        )
      end

      sig do
        params(
          scope: T.any(::Organization, ::Business),
          actor: User,
          cursor: T.nilable(String),
          repo_ids: T.nilable(T::Array[Integer]),
          exclude_repo_ids: T.nilable(T::Array[Integer]),
          repo_owners: T.nilable(RepoOwnersFilters),
          repos_in_archived_state: T.nilable(T::Boolean),
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          token_filters: T.nilable(PushProtectionTokenFilters)
        ).returns(T.nilable(SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]]))
      end
      def self.get_bypass_counts_by_repo(scope, actor, cursor = nil, repo_ids: [], exclude_repo_ids: [], repo_owners: nil, repos_in_archived_state: nil, start_date: nil, end_date: nil, token_filters: nil)
        request = {
          owner_id: scope.id,
          owner_scope: self.to_proto_owner_scope(scope),
          cursor: cursor,
          repo_ids:,
          exclude_repo_ids:,
          repo_archived_state: to_proto_repo_archived_state(repos_in_archived_state)
        }

        if token_filters
          request[:token_types] = token_filters.token_types
          request[:exclude_token_types] = token_filters.exclude_token_types
          request[:token_providers] = token_filters.token_providers
          request[:exclude_token_providers] = token_filters.exclude_token_providers
          request[:token_validities] = token_filters.token_validities
          request[:exclude_token_validities] = token_filters.exclude_token_validities
        end

        request[:repo_owners] = to_proto_repo_owners(repo_owners) if repo_owners

        if start_date.present?
          request[:start_date] = Google::Protobuf::Timestamp.new
          request[:start_date].seconds = start_date.to_time.to_i
        end

        if end_date.present?
          request[:end_date] = Google::Protobuf::Timestamp.new
          request[:end_date].seconds = end_date.to_time.to_i
        end

        response = GitHub::TokenScanning::Service::Client.new(actor).get_bypass_counts_by_repo(request)

        if response.nil? || response.error || response.data.nil?
          return nil
        end

        repo_ids = Set.new
        repos_by_id = T::let({}, T::Hash[Integer, Repository])
        bypasses_by_repository_counts = T.let([], T::Array[SecretScanning::Models::RepoCountMetric])

        response.data.counts.each do |proto|
          metric = SecretScanning::Models::RepoCountMetric.from_proto(proto)
          bypasses_by_repository_counts.push(metric)
          repo_ids.add(metric.repo_id)
        end

        Repository.where(id: repo_ids.to_a).each { |repo| repos_by_id[repo.id] = repo }

        # populate additional repo fields and filter out repos we can't find
        # we also filter out any deleted repos that may have not been synced yet
        data = bypasses_by_repository_counts.filter_map do |metric|
          if repos_by_id.has_key?(metric.repo_id)
            repo = T.must(repos_by_id[metric.repo_id])
            metric.repo_name = scope.is_a?(Business) ? repo.name_with_display_owner : repo.name

            metric if !repo.deleted?
          end
        end

        SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]].new(
          data: data,
          next_cursor: response.data.next_cursor,
          previous_cursor: response.data.previous_cursor,
        )
      end

      sig { params(owner: T.any(Repository, Organization, Business)).returns(Integer) }
      def self.to_proto_owner_scope(owner)
        case owner
        when Repository
          return GitHub::Proto::SecretScanning::Api::V1::OwnerScope::REPOSITORY_SCOPE
        when Organization
          return GitHub::Proto::SecretScanning::Api::V1::OwnerScope::ORGANIZATION_SCOPE
        when Business
          return GitHub::Proto::SecretScanning::Api::V1::OwnerScope::BUSINESS_SCOPE
        end

        T.absurd(owner)
      end
      private_class_method :to_proto_owner_scope

      sig { params(repo_owners_filters: RepoOwnersFilters).returns(GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners) }
      def self.to_proto_repo_owners(repo_owners_filters)
        filter_type =
          case repo_owners_filters.owner_type
          when RepoOwnerType::Any
            GitHub::Proto::SecretScanning::Api::V1::RepositoryOwnerFilterType::ALL
          when RepoOwnerType::Organization
            GitHub::Proto::SecretScanning::Api::V1::RepositoryOwnerFilterType::ORGANIZATION
          when RepoOwnerType::User
            GitHub::Proto::SecretScanning::Api::V1::RepositoryOwnerFilterType::USER
          end

        GitHub::Proto::SecretScanning::Api::V1::RepositoryOwners.new(
          filter_type:,
          org_ids: repo_owners_filters.org_ids,
          exclude_org_ids: repo_owners_filters.exclude_org_ids,
          user_ids: repo_owners_filters.user_ids,
          exclude_user_ids: repo_owners_filters.exclude_user_ids,
        )
      end
      private_class_method :to_proto_repo_owners

      sig do
        params(
          repo_archived_state: T.nilable(T::Boolean)
        ).returns(T.nilable(Integer))
      end
      def self.to_proto_repo_archived_state(repo_archived_state)
        return GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ANY if repo_archived_state.nil?
        return GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::ARCHIVED if repo_archived_state
        GitHub::Proto::SecretScanning::Api::V1::RepositoryArchivedState::NOT_ARCHIVED
      end
      private_class_method :to_proto_repo_archived_state

    end
  end
end
