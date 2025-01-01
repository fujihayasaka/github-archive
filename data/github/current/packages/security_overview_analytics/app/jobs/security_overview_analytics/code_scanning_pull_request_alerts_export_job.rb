# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  class CodeScanningPullRequestAlertsExportJob < BatchedJob
    extend T::Sig
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
        :query_string,
        :start_date,
        :end_date,
        :requested_at,
      ].compact.each do |kwarg|
        value = job.arguments.dig(0, kwarg)
        raise ArgumentError.new("#{kwarg} is required") if value.nil?
      end
    end

    before_perform do |_|
      job_status.started!
    end

    sig do
      params(
        business: ::Business,
        organizations: T.nilable(T::Array[::Organization]),
        user: ::User,
        query_string: String,
        start_date: ::Date,
        end_date: ::Date,
        requested_at: ::Time,
      ).returns(T.untyped)
    end
    def self.enqueue_for_business(business:, organizations:, user:, query_string:, start_date:, end_date:, requested_at:)
      self.perform_later(
        scope: business,
        organizations:,
        user:,
        query_string:,
        start_date:,
        end_date:,
        requested_at:,
        offset_item_id: nil,
      )
    end

    sig do
      params(
        organization: ::Organization,
        allowed_repo_ids: T.nilable(T::Array[Integer]),
        user: ::User,
        user_session: ::UserSession,
        query_string: String,
        start_date: ::Date,
        end_date: ::Date,
        requested_at: ::Time,
      ).returns(T.untyped)
    end
    def self.enqueue_for_organization(organization:, allowed_repo_ids:, user:, user_session:, query_string:, start_date:, end_date:, requested_at:)
      self.perform_later(
        scope: organization,
        allowed_repo_ids:,
        user:,
        user_session:,
        query_string:,
        start_date:,
        end_date:,
        requested_at:,
        offset_item_id: nil,
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
          query: Search::Queries::SecurityCenter::QueryParser.new(kwargs.fetch(:query_string)),
          start_date: kwargs.fetch(:start_date),
          end_date: kwargs.fetch(:end_date),
        )
      else
        DataExportQuery.for_organization(
          organization: scope,
          allowed_repo_ids: kwargs.fetch(:allowed_repo_ids),
          user: kwargs.fetch(:user),
          user_session: kwargs.fetch(:user_session),
          query: Search::Queries::SecurityCenter::QueryParser.new(kwargs.fetch(:query_string)),
          start_date: kwargs.fetch(:start_date),
          end_date: kwargs.fetch(:end_date),
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
      storage_service = ::SecurityCenter::Export::BlobStorageService.get(scope)
      storage_service.create(export_token, true) if offset_item_id.nil?

      csv = ExportCsvGenerator.generate(batch, offset_item_id.nil?)
      return if csv.empty?

      storage_service.store(export_token, csv, FEATURE_TYPE, true)
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
      super.merge({
        "gh.security_center.feature_type": FEATURE_TYPE,
        "gh.security_center.search.query": arguments.dig(0, :query_string),
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      }).merge(logging_context)
    end

    sig { returns(String) }
    memoize def export_token
      parser = ::Search::Queries::SecurityCenter::QueryParser.new(self.arguments.dig(0, :query_string))

      ::SecurityCenter::Export::TokenGenerator.create_token(
        user: self.arguments.dig(0, :user),
        scope: self.arguments.dig(0, :scope),
        query: parser.canonicalize,
        feature_type: FEATURE_TYPE,
        requested_at: self.arguments.dig(0, :requested_at),
        start_date: self.arguments.dig(0, :start_date),
        end_date: self.arguments.dig(0, :end_date),
      )
    end

    sig { returns(::SecurityCenter::Export::JobStatus) }
    def job_status
      status = ::SecurityCenter::Export::JobStatus.find(export_token)
      if status.nil?
        GitHub.dogstats.increment("security_center.code_scanning_pull_request_alerts_export_batched_job.job_status_not_found", tags: all_stats_tags)
        raise StandardError.new("JobStatus doesn't exist")
      end

      status
    end

    sig { params(error: StandardError, action: T.nilable(Symbol)).void }
    def report_job_error(error, action:)
      log_warn(
        "Code scanning metrics export batch job failed",
        "gh.security_center.error": error,
        "gh.security_center.job_action": action,
      )
      GitHub.dogstats.increment(
        "security_center.export.error",
        tags: [
          "scope:#{arguments.dig(0, :scope).class.to_s.downcase}",
          "feature:#{FEATURE_TYPE}",
          "action:#{action}"
          ]
        )

      job_status.error!("We couldn't generate your report. Please try again later. If the problem persists, please contact support.", ttl: 10.days)
      send_error_email
    end

    sig { void }
    def send_ready_email
      owner = arguments.dig(0, :scope)
      query = arguments.dig(0, :query_string)

      csv_url = \
        if owner.is_a?(::Business)
          UrlHelpers.enterprise_security_center_metrics_codeql_export_path(owner, export_id: export_token, format: :csv)
        else
          UrlHelpers.security_center_metrics_codeql_export_path(owner, export_id: export_token, format: :csv)
        end

      SecurityCenterMailer
        .csv_export_ready(
          user: arguments.dig(0, :user),
          owner:,
          csv_url:,
          feature: "CodeQL pull request alerts",
          query_string: query,
          end_date: arguments.dig(0, :end_date),
          row_type: "CodeQL pull request alerts",
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
      query = arguments.dig(0, :query_string)

      redirect_url = \
        if owner.is_a?(::Business)
          UrlHelpers.enterprise_security_center_metrics_codeql_path(owner, query:)
        else
          UrlHelpers.security_center_metrics_codeql_path(owner, query:)
        end

      SecurityCenterMailer
        .csv_export_error(
          user: arguments.dig(0, :user),
          owner:,
          redirect_url:,
          feature: "CodeQL pull request alerts",
          query_string: query,
          end_date: arguments.dig(0, :end_date),
        )
        .deliver_now
    end
  end
end
