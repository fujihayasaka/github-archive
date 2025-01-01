# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  class CoverageExportBatchedJob < BatchedJob
    include GitHub::SecurityCenter::LoggingHelper
    include UrlHelpers
    include GitHub::Memoizer
    include GitHub::SecurityCenter::TenantFilteringHelper

    queue_as :security_center_export

    BATCH_SIZE = SecurityCenter::Export::DataQuery::PAGE_SIZE

    before_enqueue do |job|
      scope = job.arguments.dig(0, :scope)

      [
        :scope,
        :user,
        :user_session,
        (:authorized_orgs if scope.is_a?(::Business)),
        :export_id
      ].compact.each do |kwarg|
        value = job.arguments.dig(0, kwarg)
        raise ArgumentError.new("#{kwarg} is required") if value.nil?
      end
    end

    before_perform do
      job_status.started! # call before every job to reset the TTL
    end

    sig do
      params(
        args: T.untyped,
        scope: T.any(Organization, Business),
        user: User,
        export_id: String,
        user_session: UserSession,
        offset_item_id: Integer,
        authorized_orgs: T.nilable(T::Array[Organization]),
        kwargs: T.untyped
      ).returns(T::Array[SecurityOverviewAnalytics::Coverage::ExportQuery::ListItem])
    end
    def next_batch(*args, scope:, user:, export_id:, user_session:, offset_item_id:, authorized_orgs: nil, **kwargs)
      page = offset_item_id == 0 ? 1 : offset_item_id
      @current_page = T.let(page, T.nilable(Integer))

      if scope.is_a?(Organization)
        authorized_orgs = [scope]
        allowed_repository_ids = log_timing(step: "Get allowed repository IDs by feature") do
          datadog_tags = [
            "controller:orgs_security_center_coverage_export",
            "feature:coverage",
            "scope:organization"
          ]
          AuthorizationEnumerator.new(user:, org: scope, datadog_tags:).adminable_repo_ids.first
        end
      end

      query = if scope.is_a?(Business)
        SecurityOverviewAnalytics::Coverage::ExportQuery
          .for_business(
            business: scope,
            organizations: T.must(authorized_orgs),
            user:,
            parser:,
          )
      else
        SecurityOverviewAnalytics::Coverage::ExportQuery
          .for_organization(
            organization: scope,
            repo_ids: allowed_repository_ids,
            user:,
            user_session:,
            parser:,
          )
      end

      result = query.perform(page: @current_page || 1)
      @total_pages = T.let(result.total_pages, T.nilable(Integer))
      result.items
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: "next_batch")
    end

    sig do
      params(
        batch: T::Array[SecurityOverviewAnalytics::Coverage::ExportQuery::ListItem],
        args: T.untyped,
        scope: T.any(::Business, ::Organization),
        offset_item_id: Integer,
        kwargs: T.untyped
      ).void
    end
    def process_batch(batch, *args, scope:, offset_item_id:, **kwargs)
      storage_service = Export::BlobStorageService.get
      storage_service.create(export_id) if is_first_page

      # At the org-level, get the headers for custom properties.
      # We need to pass this (rather than using the first row of data) to handle the case where a job doesn't have data.
      if scope.is_a?(Organization)
        property_headers = Repositories.domain.custom_properties.get_definitions(scope).map(&:property_name)
      end

      csv = Coverage::ExportCsvGenerator.generate(batch, property_headers:, write_headers: is_first_page, owner: scope)
      return if csv.empty?

      storage_service.store(export_id, csv, "coverage")
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: "process_batch")
    end

    sig do
      params(
        batch: T::Array[{}],
        args: T.untyped,
        scope: T.any(Organization, Business),
        user: User,
        user_session: UserSession,
        offset_item_id: Integer,
        authorized_orgs: T.nilable(T::Array[Organization]),
        kwargs: T.untyped
      ).void
    end
    def finalize_batch(batch, *args, scope:, user:, user_session:, offset_item_id:, authorized_orgs: nil, **kwargs)
      return if has_next_batch?(batch)

      GitHub.logger.info(
        "Finalizing batches for current feature",
        "code.namespace": self.class.name,
        "code.function": __method__
      )

      job_status.success!

      csv_url = if scope.is_a?(Organization)
        security_center_coverage_get_export_path(scope, export_id:, format: :csv)
      else
        security_center_coverage_get_export_enterprise_path(scope, export_id:, format: :csv)
      end

      begin
        SecurityCenterMailer.csv_export_ready(
          user:,
          owner: scope,
          csv_url:,
          feature: "coverage",
          query_string:,
          end_date: requested_at.to_date,
          row_type: "repository enablement statuses",
          file_expiration: ::SecurityCenter::Export::BlobStorageService::FILE_EXPIRY.from_now,
        ).deliver_now
      rescue => e # rubocop:disable Lint/GenericRescue
        Failbot.report(e)
        log_warn(
          "Coverage export failed to send an email",
          "gh.security_center.error": e
        )
        GitHub.dogstats.increment("security_center.export.error", tags: ["scope:#{scope.class.to_s.downcase}", "feature:coverage", "action:send_email"])
      end
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: "finalize_batch")
    end

    sig do
      override
        .params(batch: T::Array[{}], args: T.untyped, options: T.untyped)
        .returns(T.nilable(Integer))
    end
    def next_batch_offset_item_id(batch, *args, **options)
      T.must(@current_page) + 1
    end

    sig do
      override
        .params(batch: T::Array[{}], options: T.untyped)
        .returns(T::Boolean)
    end
    def has_next_batch?(batch, **options)
      T.must(@current_page) < T.must(@total_pages)
    end

    private

    sig { returns(String) }
    def query_string
      job_status.query
    end

    sig { returns(Time) }
    def requested_at
      Time.parse(job_status.requested_at)
    end

    sig { returns(String) }
    def export_id
      self.arguments.dig(0, :export_id)
    end

    sig { returns(T.any(Organization, Business)) }
    def scope
      self.arguments.dig(0, :scope)
    end

    sig { returns(T::Boolean) }
    def is_first_page
      # Check all the possibilities for the first page.
      # Default parameter values don't show up in `job.arguments`, so
      # the offset_item_id could be nil if the user didn't pass the param.
      [nil, 0, 1].include?(self.arguments.dig(0, :offset_item_id))
    end

    sig { returns(Export::JobStatus) }
    memoize def job_status
      status = ::SecurityCenter::Export::JobStatus.find(export_id)
      if status.nil?
        GitHub.dogstats.increment("security_center.coverage_export_batched_job.job_status_not_found", tags: all_stats_tags)
        raise RuntimeError.new("JobStatus doesn't exist")
      end

      status
    end

    sig { returns(::Search::Queries::SecurityCenter::CoverageQueryParser) }
    memoize def parser
      ::Search::Queries::SecurityCenter::CoverageQueryParser.new(query_string)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      scope = arguments.dig(0, :scope)
      scope_type = scope.class.to_s.downcase
      offset_item_id = arguments.dig(0, :offset_item_id)

      super.merge({
        "gh.security_center.feature_type": "coverage",
        "gh.security_center.search.query": arguments.dig(0, :query_string),
        "gh.security_center.offset_item_id": offset_item_id,
        "gh.security_center.scope": scope_type,
        "gh.security_center.scope_id": scope.id,
        "gh.security_center.scope_login": scope.display_login,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      }).merge(logging_context)
    end

    sig { params(error: StandardError, action: String).returns(T.noreturn) }
    def report_job_error(error, action:)
      scope = arguments.dig(0, :scope)
      scope_type = scope.class.to_s.downcase

      log_warn(
        "Coverage export batch job failed",
        "gh.security_center.error": error,
        "gh.security_center.job_action": action,
      )
      GitHub.dogstats.increment(
        "security_center.export.error",
        tags: [
          "scope:#{scope_type}",
          "feature:coverage",
          "action:#{action}"
          ]
        )

      send_error_email
      job_status.error!(ttl: 10.days)

      raise error
    end

    sig { void }
    def send_error_email
      user = self.arguments.dig(0, :user)

      redirect_url = if scope.is_a?(Organization)
        security_center_coverage_path(scope, export_id:, format: :csv)
      else
        security_center_coverage_enterprise_path(scope, export_id:, format: :csv)
      end

      SecurityCenterMailer.csv_export_error(
        user:,
        owner: scope,
        redirect_url:,
        feature: "coverage",
        query_string:,
        end_date: requested_at.to_date
      ).deliver_now
    end

    sig { params(items: ActiveRecord::Relation, scope: T.any(Organization, Business)).returns(T::Array[::Repository]) }
    def apply_tenant_filter(items, scope)
      request_scope = scope.is_a?(::Business) ? :business : :organization
      filter_tenant_rows(
        RequestScope.new(request_scope, scope, "coverage-export"),
        items,
        -> (r) { r.id }
      ).first
    end
  end
end
