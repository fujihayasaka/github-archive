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
        max_id: T.nilable(Integer),
        # The min exemption request ID to query for. Used as a keyset cursor when
        # sorting ascending by id. Skips this condition if nil.
        min_id: T.nilable(Integer),
        sort: T.nilable(String)
      )
      .returns(ActiveRecord::Relation)
    end
    def self.base_sql_for_exemption_requests(
      source,
      request_types: [],
      repository: nil,
      organization: nil,
      request_status: "all",
      approver: nil,
      requester: nil,
      time_period: "day",
      limit: nil,
      max_id: nil,
      min_id: nil,
      sort: nil
    )
      # We need to treat queries for secret/code scanning different from queries for rulesets
      # because for rulesets we need to join on another table for faster performance
      # But request_types can either be a single entry for secret/code scanning,
      # or multiple entries for rulesets
      # So if there are more than one entry or if the first entry is not secret/code scanning,
      # then assume it's for rulesets
      scanning_request = request_types.first == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE ||
        request_types.first == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE ||
        request_types.first == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE ||
        request_types.first == Dependabot::SecurityProduct::DelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE ||
        request_types.first == DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE

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

      if min_id.present?
        base_sql = base_sql.where("exemption_requests.id > ?", min_id)
      end

      # Avoid duplicating predicates that `for_source` / `for_ruleset_source`
      # already added when the caller passes the same record as both the
      # positional `source` and the `repository:` / `organization:` kwarg.
      # MySQL collapses identical predicates at plan time, but logging the
      # duplicate is noisy in slow-query logs and trace.github.internal.
      if repository.present? && source != repository
        base_sql = base_sql.where(repository:)
      end
      if organization.present? && source != organization
        base_sql = base_sql.where(owner: organization)
      end

      if request_types.any?
        base_sql = base_sql.where(request_type: request_types)
      end

      case request_status
      when "completed"
        if request_types.first == CodeScanning::AlertDismissalService::EXEMPTION_REQUEST_TYPE ||
            request_types.first == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE ||
            request_types.first == DependencyGraph::LicenseComplianceDelegatedClosures::CLOSURE_EXEMPTION_REQUEST_TYPE
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

      sorting_for_supported_types = request_types.present? && request_types.all? do |request_type|
        request_type == SecretScanning::ExemptionConstants::CLOSURE_EXEMPTION_REQUEST_TYPE ||
          request_type == SecretScanning::Constants::EXEMPTION_REQUEST_TYPE
      end

      if sorting_for_supported_types
        case sort
        when "created-asc"
          base_sql = base_sql.reorder(created_at: :asc, id: :asc)
        when "created-desc"
          base_sql = base_sql.reorder(created_at: :desc, id: :desc)
        when "updated-asc"
          base_sql = base_sql.reorder(updated_at: :asc, id: :asc)
        when "updated-desc"
          base_sql = base_sql.reorder(updated_at: :desc, id: :desc)
        end
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
        sort: T.nilable(String),
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
      request_types: [],
      sort: nil
    )
      return [], false unless page >= 1

      sorting_enabled = sort.present?

      # Wrap the whole pagination loop in a span so we can compare old (unsorted /
      # id-only cursor) vs new (sorted / composite cursor) query shapes in
      # trace.github.internal. Attributes are chosen to be groupable filters.
      GitHub.tracer.in_span(
        "Exemptions::BatchExemptionRequestQuery#fetch_exemption_requests_with_permissions_checking",
        kind: :internal,
        attributes: {
          "gh.exemption_requests.source_type" => @source.class.name,
          "gh.exemption_requests.source_id" => @source.id,
          "gh.exemption_requests.sort" => sort.to_s,
          "gh.exemption_requests.sorting_enabled" => sorting_enabled,
          "gh.exemption_requests.page" => page,
          "gh.exemption_requests.page_size" => page_size,
          "gh.exemption_requests.limit" => limit,
          "gh.exemption_requests.request_status" => request_status.to_s,
          "gh.exemption_requests.time_period" => time_period.to_s,
          "gh.exemption_requests.request_types" => request_types.join(","),
        },
      ) do
        authorized_repo_ids = Set.new
        unauthorized_repo_ids = Set.new
        exemption_requests = []
        # Dedupe by id so each request appears at most once even if concurrent
        # writes re-order rows while this query paginates.
        seen_ids = T.let(Set.new, T::Set[Integer])
        start_index = page_size * (page - 1)
        # The end index is inclusive, so we need to subtract 1 from the page size
        end_index_inclusive = start_index + page_size - 1
        # The total number of exemptions to fetch, including those we have to skip, is end_index_inclusive + 1.
        # However, we add the additional 1 in order to determine if there are more exemptions (for the has_more boolean return value).
        total_exemptions_to_fetch = end_index_inclusive + 2

        shared_args = {
          request_types:, repository:, organization:, request_status:,
          approver:, requester:, time_period:, limit:,
        }

        # For `updated-*` sorts, capture a request-level snapshot so rows updated
        # mid-pagination do not jump across page boundaries.
        snapshot_updated_before = T.let(nil, T.nilable(Time))
        if sorting_enabled && (sort == "updated-asc" || sort == "updated-desc")
          snapshot_updated_before = Time.now
        end

        cursor_timestamp = T.let(nil, T.nilable(Time))
        cursor_id = T.let(nil, T.nilable(Integer))
        batch_index = 0

        loop do
          scope = self.class.base_sql_for_exemption_requests(
            @source,
            **shared_args,
            sort: sorting_enabled ? sort : nil,
          )
          scope = apply_updated_snapshot_fence(scope, sort: sorting_enabled ? sort : nil, snapshot_updated_before:)
          scope = apply_keyset_cursor(scope, sort: sorting_enabled ? sort : nil, cursor_timestamp:, cursor_id:)

          # Child span per DB batch hit. `cursor_kind` lets us distinguish the
          # old id-only predicate from the new composite (timestamp, id)
          # predicate in traces.
          batch = GitHub.tracer.in_span(
            "Exemptions::BatchExemptionRequestQuery#fetch_batch",
            kind: :internal,
            attributes: {
              "gh.exemption_requests.batch_index" => batch_index,
              "gh.exemption_requests.cursor_kind" => cursor_kind_for(sorting_enabled:, sort:, cursor_id:),
            },
          ) do
            scope.to_a
          end
          break if batch.empty?

          process_batch(
            batch:, user:, fgp:,
            authorized_repo_ids:, unauthorized_repo_ids:,
            exemption_requests:, seen_ids:,
          )

          last = batch.last

          cursor_timestamp = cursor_timestamp_for_sort(last, sort: sorting_enabled ? sort : nil)
          cursor_id = last.id
          batch_index += 1

          break if exemption_requests.count >= total_exemptions_to_fetch
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

    private

    sig do
      params(
        scope: T.untyped,
        sort: T.nilable(String),
        snapshot_updated_before: T.nilable(Time),
      ).returns(T.untyped)
    end
    def apply_updated_snapshot_fence(scope, sort:, snapshot_updated_before:)
      return scope unless snapshot_updated_before.present?
      return scope unless sort == "updated-asc" || sort == "updated-desc"

      scope.where("exemption_requests.updated_at <= ?", snapshot_updated_before)
    end

    sig do
      params(
        scope: T.untyped,
        sort: T.nilable(String),
        cursor_timestamp: T.nilable(Time),
        cursor_id: T.nilable(Integer),
      ).returns(T.untyped)
    end
    def apply_keyset_cursor(scope, sort:, cursor_timestamp:, cursor_id:)
      return scope unless cursor_timestamp.present? && cursor_id.present?

      case sort
      when "created-asc"
        scope.where(
          "(exemption_requests.created_at > :ts) OR " \
          "(exemption_requests.created_at = :ts AND exemption_requests.id > :id)",
          ts: cursor_timestamp,
          id: cursor_id,
        )
      when "updated-asc"
        scope.where(
          "(exemption_requests.updated_at > :ts) OR " \
          "(exemption_requests.updated_at = :ts AND exemption_requests.id > :id)",
          ts: cursor_timestamp,
          id: cursor_id,
        )
      when "updated-desc"
        scope.where(
          "(exemption_requests.updated_at < :ts) OR " \
          "(exemption_requests.updated_at = :ts AND exemption_requests.id < :id)",
          ts: cursor_timestamp,
          id: cursor_id,
        )
      when "created-desc"
        scope.where(
          "(exemption_requests.created_at < :ts) OR " \
          "(exemption_requests.created_at = :ts AND exemption_requests.id < :id)",
          ts: cursor_timestamp,
          id: cursor_id,
        )
      else
        # Default path (sorting feature flag off / unknown sort)
        scope.where("exemption_requests.id < ?", cursor_id)
      end
    end

    sig { params(exemption_request: Exemptions::ExemptionRequest, sort: T.nilable(String)).returns(Time) }
    def cursor_timestamp_for_sort(exemption_request, sort:)
      if sort == "updated-asc" || sort == "updated-desc"
        exemption_request.updated_at
      else
        exemption_request.created_at
      end
    end

    # Telemetry-only label describing the keyset cursor predicate shape applied
    # to the current batch. Used as a span attribute so old (id-only) and new
    # (composite) query paths are filterable in trace.github.internal.
    sig do
      params(
        sorting_enabled: T.nilable(T::Boolean),
        sort: T.nilable(String),
        cursor_id: T.nilable(Integer),
      ).returns(String)
    end
    def cursor_kind_for(sorting_enabled:, sort:, cursor_id:)
      return "none" if cursor_id.nil?
      return "id_only" unless sorting_enabled

      case sort
      when "created-asc"  then "created_asc_composite"
      when "created-desc" then "created_desc_composite"
      when "updated-asc"  then "updated_asc_composite"
      when "updated-desc" then "updated_desc_composite"
      else "id_only"
      end
    end

    # Resolves authorization for any new repository IDs in `batch` and appends
    # the authorized exemption requests onto `exemption_requests`. Mutates the
    # repo-id sets so subsequent batches reuse the already-resolved decisions.
    sig do
      params(
        batch: T::Array[Exemptions::ExemptionRequest],
        user: User,
        fgp: Symbol,
        authorized_repo_ids: T::Set[Integer],
        unauthorized_repo_ids: T::Set[Integer],
        exemption_requests: T::Array[Exemptions::ExemptionRequest],
        seen_ids: T::Set[Integer],
      ).void
    end
    def process_batch(batch:, user:, fgp:, authorized_repo_ids:, unauthorized_repo_ids:, exemption_requests:, seen_ids:)
      candidate_repo_ids = Set.new(batch.map(&:repository_id))
      candidate_repo_ids.subtract(authorized_repo_ids)
      candidate_repo_ids.subtract(unauthorized_repo_ids)

      if candidate_repo_ids.present?
        auth_enumerator = SecurityProduct::AuthorizationEnumerator.new(
          user: user,
          actions: [fgp],
          options: { repository_ids: candidate_repo_ids.to_a },
        )
        batch_authorized = Set.new(auth_enumerator.authorized_repository_ids)
        authorized_repo_ids.merge(batch_authorized)
        unauthorized_repo_ids.merge(candidate_repo_ids - batch_authorized)
      end

      batch.each do |exemption_request|
        next unless authorized_repo_ids.include?(exemption_request.repository_id)
        next unless seen_ids.add?(exemption_request.id)
        exemption_requests << exemption_request
      end
    end
  end
end
