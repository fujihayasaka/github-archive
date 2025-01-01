# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  class CodeScanningPullRequestAlertsExportJob < BatchedJob
    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper

    queue_as :security_center_export

    # Because retrying the job may result in writing duplicate records to the CSV,
    # we do not automatically retry on any known error. We notify the user and they can try again.
    # retry_on_dirty_exit

    DataExportQuery = ::SecurityOverviewAnalytics::Dashboards::CodeScanningMetrics::Queries::DataExportQuery
    ExportCsvGenerator = ::SecurityOverviewAnalytics::Dashboards::CodeScanningMetrics::ExportCsvGenerator
    FEATURE_TYPE = "code_scanning_metrics"

    before_enqueue do |job|
      scope = job.arguments.dig(0, :scope)
      raise ArgumentError.new("scope is required") if scope.nil?
      [
        (:organizations if scope.is_a?(::Business)),
        # allowed_repo_ids is optional for org-scope exports
        :user,
        (:user_session if scope.is_a?(::Organization)),
        :export_id
      ].compact.each do |kwarg|
        value = job.arguments.dig(0, kwarg)
        raise ArgumentError.new("#{kwarg} is required") if value.nil?
      end
    end

    before_perform do |_|
      job_status.started! # call before every job to reset the TTL
    end

    sig do
      params(
        business: ::Business,
        organizations: T.nilable(T::Array[::Organization]),
        user: ::User,
        export_id: String
      ).returns(T.untyped)
    end
    def self.enqueue_for_business(business:, organizations:, user:, export_id:)
      self.perform_later(
        scope: business,
        organizations:,
        user:,
        offset_item_id: nil,
        export_id:
      )
    end

    sig do
      params(
        organization: ::Organization,
        allowed_repo_ids: T.nilable(T::Array[Integer]),
        user: ::User,
        user_session: ::UserSession,
        export_id: String
      ).returns(T.untyped)
    end
    def self.enqueue_for_organization(organization:, allowed_repo_ids:, user:, user_session:, export_id:)
      self.perform_later(
        scope: organization,
        allowed_repo_ids:,
        user:,
        user_session:,
        offset_item_id: nil,
        export_id:
      )
    end

    sig do
      override
        .params(
          args: T.untyped,
          scope: T.any(::Business, ::Organization),
          offset_item_id: T.nilable(String),
          kwargs: T.untyped,
        )
        .returns(DataExportQuery::Result)
    end
    def next_batch(*args, scope:, offset_item_id:, **kwargs)
      query = if scope.is_a?(::Business)
        DataExportQuery.for_business(
          business: scope,
          organizations: kwargs.fetch(:organizations),
          user: kwargs.fetch(:user),
          query: Search::Queries::SecurityCenter::QueryParser.new(query_string),
          start_date:,
          end_date:,
        )
      else
        DataExportQuery.for_organization(
          organization: scope,
          allowed_repo_ids: kwargs.fetch(:allowed_repo_ids),
          user: kwargs.fetch(:user),
          user_session: kwargs.fetch(:user_session),
          query: Search::Queries::SecurityCenter::QueryParser.new(query_string),
          start_date:,
          end_date:,
        )
      end

      query.perform(cursor: offset_item_id)
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: __method__)
      raise
    end

    sig do
      override
        .params(
          batch: DataExportQuery::Result,
          args: T.untyped,
          scope: T.any(::Business, ::Organization),
          offset_item_id: T.nilable(String),
          kwargs: T.untyped,
        )
        .void
    end
    def process_batch(batch, *args, scope:, offset_item_id:, **kwargs)
      storage_service = ::SecurityCenter::Export::BlobStorageService.get
      storage_service.create(export_id) if offset_item_id.nil?

      # At the org-level, get the headers for custom properties.
      # We need to pass this (rather than using the first row of data) to handle the case where a job doesn't have data.
      if scope.is_a?(Organization)
        manager = CustomProperties::Public.definitions_manager(scope)
        custom_properties = manager.get_definitions.map(&:property_name)
      end

      csv = ExportCsvGenerator.generate(batch, custom_properties, offset_item_id.nil?)
      return if csv.empty?

      storage_service.store(export_id, csv, FEATURE_TYPE)
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: __method__)
      raise
    end

    sig do
      override
        .params(batch: DataExportQuery::Result, args: T.untyped, kwargs: T.untyped)
        .void
    end
    def finalize_batch(batch, *args, **kwargs)
      return if has_next_batch?(batch)

      GitHub.logger.info(
        "Finalizing batches for current feature",
        "code.namespace": self.class.name,
        "code.function": __method__
      )

      job_status.success!
      send_ready_email
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: __method__)
      raise
    end

    sig do
      override
        .params(batch: DataExportQuery::Result, args: T.untyped, kwargs: T.untyped)
        .returns(T.nilable(String))
    end
    def next_batch_offset_item_id(batch, *args, **kwargs)
      batch.next
    end

    sig do
      override
        .params(batch: DataExportQuery::Result, kwargs: T.untyped)
        .returns(T::Boolean)
    end
    def has_next_batch?(batch, **kwargs)
      batch.next.present?
    end

    private

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      scope = arguments.dig(0, :scope)
      scope_type = scope.class.to_s.downcase
      offset_item_id = arguments.dig(0, :offset_item_id)

      super.merge({
        "gh.security_center.feature_type": FEATURE_TYPE,
        "gh.security_center.search.query": query_string,
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

    sig { returns(String) }
    def query_string
      job_status.query
    end

    sig { returns(Time) }
    def requested_at
      Time.parse(job_status.requested_at)
    end

    sig { returns(::Date) }
    def start_date
      T.must(job_status.start_date).to_date
    end

    sig { returns(::Date) }
    def end_date
      T.must(job_status.end_date).to_date
    end

    sig { returns(String) }
    def export_id
      self.arguments.dig(0, :export_id)
    end

    sig { returns(::SecurityCenter::Export::JobStatus) }
    memoize def job_status
      status = ::SecurityCenter::Export::JobStatus.find(export_id)
      if status.nil?
        GitHub.dogstats.increment("security_center.code_scanning_pull_request_alerts_export_batched_job.job_status_not_found", tags: all_stats_tags)
        raise StandardError.new("JobStatus doesn't exist")
      end

      status
    end

    sig { params(error: StandardError, action: T.nilable(Symbol)).void }
    def report_job_error(error, action:)
      scope = arguments.dig(0, :scope)
      scope_type = scope.class.to_s.downcase
      offset_item_id = arguments.dig(0, :offset_item_id)

      log_warn(
        "Code scanning metrics export batch job failed",
        "gh.security_center.error": error,
        "gh.security_center.job_action": action,
        "gh.security_center.offset_item_id": offset_item_id,
        "gh.security_center.scope": scope_type,
        "gh.security_center.scope_id": scope.id,
        "gh.security_center.scope_login": scope.display_login,
      )
      GitHub.dogstats.increment(
        "security_center.export.error",
        tags: [
          "scope:#{scope_type}",
          "feature:#{FEATURE_TYPE}",
          "action:#{action}"
          ]
        )

      job_status.error!(ttl: 10.days)
      send_error_email
    end

    sig { void }
    def send_ready_email
      owner = arguments.dig(0, :scope)

      csv_url = \
        if owner.is_a?(::Business)
          UrlHelpers.enterprise_security_center_metrics_codeql_export_path(owner, export_id:, format: :csv)
        else
          UrlHelpers.security_center_metrics_codeql_export_path(owner, export_id:, format: :csv)
        end

      SecurityCenterMailer
        .csv_export_ready(
          user: arguments.dig(0, :user),
          owner:,
          csv_url:,
          feature: "CodeQL pull request alerts",
          query_string:,
          end_date:,
          row_type: "CodeQL pull request alerts",
          file_expiration: ::SecurityCenter::Export::BlobStorageService::FILE_EXPIRY.from_now,
        )
        .deliver_now
    rescue => e # rubocop:disable Lint/GenericRescue
      # We don't want to mark the job as failed because of email. Log and swallow.
      Failbot.report(e)
      log_warn(
        "CodeQL pull request alerts export failed to send an email",
        "gh.security_center.error": e
      )
      GitHub.dogstats.increment("security_center.export.error", tags: [
        "scope:#{owner.class.to_s.downcase}",
        "feature:#{FEATURE_TYPE}",
        "action:send_ready_email"
      ])
    end

    sig { void }
    def send_error_email
      owner = arguments.dig(0, :scope)

      redirect_url = \
        if owner.is_a?(::Business)
          UrlHelpers.enterprise_security_center_metrics_codeql_path(owner, query: query_string)
        else
          UrlHelpers.security_center_metrics_codeql_path(owner, query: query_string)
        end

      SecurityCenterMailer
        .csv_export_error(
          user: arguments.dig(0, :user),
          owner:,
          redirect_url:,
          feature: "CodeQL pull request alerts",
          query_string:,
          end_date:,
        )
        .deliver_now
    end
  end
end
