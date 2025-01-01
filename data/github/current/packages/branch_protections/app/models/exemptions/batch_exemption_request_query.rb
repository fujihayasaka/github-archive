# typed: strict
# frozen_string_literal: true

module Exemptions
  class BatchExemptionRequestQuery

    # The default page size for batch exemption request queries
    DEFAULT_BATCH_EXEMPTION_REQUEST_PAGE_SIZE = 10

    sig { params(source: T.any(Organization, Business)).void }
    def initialize(source)
      @source = source
    end

    sig { params(exemption_requests: T::Array[Exemptions::ExemptionRequest]).void }
    def self.mark_exemption_requests_as_deleted_if_necessary(exemption_requests)
      repository_lookup = ::Repositories.domain.by_ids(exemption_requests.map(&:repository_id), allow_deleted: false).each_with_object({}) do |repository, hash|
        hash[repository.id] = true
      end

      exemption_requests = exemption_requests.each do |exemption_request|
        next exemption_request if repository_lookup.key?(exemption_request.repository_id)

        # if we cannot find the repo, it has likely been deleted
        # so update any pending requests as deleted, but keep all requests and the repo id so we can show users
        exemption_request.status = :deleted if exemption_request.pending?
      end
    end

    sig do params(
        source: RuleEngine::Types::RuleSource,
        request_types: T::Array[String],
        repository: T.nilable(Repository),
        organization: T.nilable(Organization),
        request_status: T.nilable(String),
        approver: T.untyped,
        requester: T.untyped,
        time_period: T.nilable(String),
        # The number of exemption requests to return.
        limit: T.nilable(Integer),
        # The max exemption request ID to query for. Skips this condition if nil.
        max_id: T.nilable(Integer)
      )
      .returns(ActiveRecord::Relation)
    end
    def self.base_sql_for_exemption_requests(source, request_types: [], repository: nil, organization: nil, request_status: "all", approver: nil, requester: nil, time_period: "day", limit: nil, max_id: nil)

      # We need to treat queries for secret/code scanning different from queries for rulesets
      # because for rulesets we need to join on another table for faster performance
      # But request_types can either be a single entry for secret/code scanning,
      # or multiple entries for rulesets
      # So if there are more than one entry or if the first entry is not secret/code scanning,
      # then assume it's for rulesets
      scanning_request = request_types.first == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE ||
        request_types.first == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE ||
        request_types.first == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE

      base_sql =
      if request_types.count == 1 && scanning_request
        Exemptions::ExemptionRequest.for_source(source)
      else
        Exemptions::ExemptionRequest.for_ruleset_source(source)
      end.order(created_at: :desc)

      if limit.present?
        base_sql = base_sql.limit(limit)
      end

      if max_id.present?
        base_sql = base_sql.where("exemption_requests.id < ?", max_id)
      end

      base_sql = base_sql.where(repository: repository) if repository.present?
      base_sql = base_sql.where(owner: organization) if organization.present?

      if request_types.any?
        base_sql = base_sql.where(request_type: request_types)
      end

      case request_status
      when "completed"
        if request_types.first == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE || request_types.first == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE
          base_sql = base_sql.where(status: %w(approved rejected))
        else
          base_sql = base_sql.where(status: "completed")
        end
      when "approved"
        base_sql = base_sql.where(status: "approved")
      when "cancelled"
        base_sql = base_sql.where(status: "cancelled")
      when "expired"
        base_sql = base_sql.where(status: "pending").and(base_sql.where(expires_at: ..Time.now))
      when "denied"
        base_sql = base_sql.where(status: "rejected")
      when "open"
        base_sql = base_sql.where(status: "pending").and(base_sql.not_expired)
      end

      case time_period
      when "hour"
        base_sql = base_sql.where(created_at: 1.hour.ago..)
      when "day"
        base_sql = base_sql.where(created_at: 1.day.ago..)
      when "week"
        base_sql = base_sql.where(created_at: 1.week.ago..)
      when "month"
        base_sql = base_sql.where(created_at: 1.month.ago..)
      end

      if requester.present?
        base_sql = base_sql.where(requester_id: requester.id)
      end

      if approver.present?
        base_sql = base_sql.joins("INNER JOIN exemption_responses ON
            exemption_requests.id = exemption_responses.exemption_request_id
            AND exemption_requests.repository_id = exemption_responses.repository_id")
        .where("exemption_responses.reviewer_id = ?", approver)
        .distinct
      end

      base_sql = base_sql.annotate("cross-shard-query-exempted")

      base_sql
    end

    sig do
      params(
        user: User,
        fgp: Symbol,
        repository: T.nilable(Repository),
        organization: T.nilable(Organization),
        limit: Integer,
        page: Integer,
        page_size: Integer,
        requester: T.untyped,
        approver: T.untyped,
        time_period: T.nilable(String),
        request_status: T.nilable(String),
        request_types: T::Array[String],
      ).returns([T::Array[Exemptions::ExemptionRequest], T::Boolean])
    end
    def fetch_exemption_requests_with_permissions_checking(
      user,
      fgp,
      repository: nil,
      organization: nil,
      limit: SecretScanning::ExemptionConstants::EXEMPTION_REQUEST_BATCH_SIZE_LIMIT,
      # 1-offset pagination, because that's what the UI expects
      page: 1,
      page_size: DEFAULT_BATCH_EXEMPTION_REQUEST_PAGE_SIZE,
      requester: nil,
      approver: nil,
      time_period: "day",
      request_status: "all",
      request_types: []
    )
      return [], false unless page >= 1

      authorized_repo_ids = Set.new
      unauthorized_repo_ids = Set.new
      exemption_requests = []
      start_index = page_size * (page - 1)
      # The end index is inclusive, so we need to subtract 1 from the page size
      end_index_inclusive = start_index + page_size - 1
      # The total number of exemptions to fetch, including those we have to skip, is end_index_inclusive + 1.
      # However, we add the additional 1 in order to determine if there are more exemptions (for the has_more boolean return value).
      total_exemptions_to_fetch = end_index_inclusive + 2

      current_batch = T.let(nil, T.nilable(T::Array[Exemptions::ExemptionRequest]))
      max_id = T.let(nil, T.nilable(Integer))

      while current_batch.nil? || exemption_requests.count < total_exemptions_to_fetch
        base_sql = self.class.base_sql_for_exemption_requests(@source, request_types:, repository:, organization:, request_status:, approver:, requester:, time_period:, limit:, max_id:)

        current_batch = base_sql.to_a

        break if current_batch.empty?

        current_batch_by_repo_id = current_batch.group_by(&:repository_id)
        candidate_repo_ids = Set.new(current_batch_by_repo_id.keys)
        # Remove repo IDs that we've already processed, since we know their authorization status.
        candidate_repo_ids.subtract(authorized_repo_ids)
        candidate_repo_ids.subtract(unauthorized_repo_ids)

        # See if there are any new repo IDs to check
        if candidate_repo_ids.present?
          auth_enumerator = SecurityProduct::AuthorizationEnumerator.new(user: user, actions: [fgp], options: { repository_ids: candidate_repo_ids.to_a })
          batch_authorized_repo_ids = Set.new(auth_enumerator.authorized_repository_ids)
          authorized_repo_ids.merge(batch_authorized_repo_ids)
          unauthorized_repo_ids.merge(candidate_repo_ids - batch_authorized_repo_ids)
        end

        # Filter out exemption requests that are not authorized
        current_batch.each do |exemption_request|
          # If the user is not authorized to view the exemption request, skip it
          next unless authorized_repo_ids.include?(exemption_request.repository_id)
          exemption_requests << exemption_request
        end

        # The batch is ordered by 'created_at desc', so the last item in the batch is the oldest i.e with the smallest id. We want the next batch to only include exemption_requests with a smaller (older) id.
        max_id = current_batch.last&.id
      end

      # This happens if the page is too large and there are no more exemption requests to fetch
      if start_index >= exemption_requests.count
        return [], false
      end

      exemptions_to_return = T.must(exemption_requests[start_index..end_index_inclusive])

      has_more = false
      if end_index_inclusive + 1 < exemption_requests.count
        # We deliberately tried to fetch an additional exemption request, to determine whether or not there are more.
        # If that worked, there are more.
        has_more = true
      end

      self.class.mark_exemption_requests_as_deleted_if_necessary(exemptions_to_return)
      [exemptions_to_return, has_more]
    end

  end
end
