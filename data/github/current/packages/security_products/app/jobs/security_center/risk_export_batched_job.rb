# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  class RiskExportBatchedJob < BatchedJob
    include GitHub::SecurityCenter::LoggingHelper
    include UrlHelpers
    include GitHub::Memoizer
    include GitHub::SecurityCenter::TenantFilteringHelper

    queue_as :security_center_export

    BATCH_SIZE = SecurityCenter::Export::DataQuery::PAGE_SIZE
    RepositoryRowResult = T.type_alias do
      T.any(
        SecurityCenter::Risk::ExportDataQuery::RepositoryRowResult,
        SecurityOverviewAnalytics::Risk::ExportQuery::ListItem,
      )
    end

    before_enqueue do |job|
      scope = job.arguments.dig(0, :scope)

      if scope.is_a?(::Business) && job.arguments.dig(0, :authorized_orgs).nil? && job.arguments.dig(0, :authorized_orgs_by_action).nil?
        raise ArgumentError.new("authorized_orgs or authorized_orgs_by_action is required")
      end

      [
        :scope,
        :user,
        :user_session,
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
        authorized_orgs: T.nilable(T::Hash[String, T::Array[::Organization]]),
        authorized_orgs_by_action: T.nilable(T::Hash[String, T::Array[::Organization]]),
        kwargs: T.untyped
      ).returns(T::Array[RepositoryRowResult])
    end
    def next_batch(*args, scope:, user:, export_id:, user_session:, offset_item_id:, authorized_orgs: nil, authorized_orgs_by_action: nil, **kwargs)
      page = offset_item_id == 0 ? 1 : offset_item_id
      @current_page = T.let(page, T.nilable(Integer))

      if scope.is_a?(Organization)
        allowed_repository_ids_by_feature = log_timing(step: "Get allowed repository IDs by feature") do
          datadog_tags = [
            "controller:orgs_security_center_risk_export",
            "feature:risk",
            "scope:organization"
          ]
          AuthorizationEnumerator.new(user:, org: scope, datadog_tags:).allowed_repository_ids_by_feature
        end
      end

      query = if scope.is_a?(Business)
        authorized_orgs = T.let(authorized_orgs&.symbolize_keys, T.nilable(T::Hash[Symbol, T::Array[::Organization]]))
        authorized_orgs_by_action = T.let(authorized_orgs_by_action&.symbolize_keys, T.nilable(T::Hash[Symbol, T::Array[::Organization]]))

        authorized_orgs_by_feature = T.must(
          authorized_orgs || authorized_orgs_by_action&.transform_keys do |k|
            case k
            when :read_code_scanning; :code_scanning
            when :view_dependabot_alerts; :dependabot_alerts
            when :view_secret_scanning_alerts; :secret_scanning_alerts
            else
              raise ArgumentError.new("Unexpected action: #{k}")
            end
          end
        )

        SecurityOverviewAnalytics::Risk::ExportQuery
          .for_business(
            business: scope,
            organizations: authorized_orgs_by_feature,
            user:,
            parser:,
          )
      else
        SecurityOverviewAnalytics::Risk::ExportQuery
          .for_organization(
            organization: scope,
            repo_ids_by_feature: allowed_repository_ids_by_feature,
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
        batch: T::Array[RepositoryRowResult],
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
      if scope.is_a?(Organization) && FeatureFlagHelper.risk_export_include_repo_properties?(scope)
        manager = CustomProperties::Public.definitions_manager(scope)
        property_headers = manager.get_definitions.map(&:property_name)
      end

      csv = Risk::ExportCsvGenerator.generate(batch, property_headers:, write_headers: is_first_page, owner: scope)
      return if csv.empty?

      storage_service.store(export_id, csv, "risk")
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
        authorized_orgs: T.nilable(T::Hash[String, T::Array[::Organization]]),
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
        security_center_risk_get_export_path(scope, export_id:, format: :csv)
      else
        security_center_risk_get_export_enterprise_path(scope, export_id:, format: :csv)
      end

      begin
        SecurityCenterMailer.csv_export_ready(
          user:,
          owner: scope,
          csv_url:,
          feature: "risk",
          query_string:,
          end_date: requested_at.to_date,
          row_type: "repository alert counts",
          file_expiration: ::SecurityCenter::Export::BlobStorageService::FILE_EXPIRY.from_now,
        ).deliver_now
      rescue => e # rubocop:disable Lint/GenericRescue
        Failbot.report(e)
        log_warn(
          "Risk export failed to send an email",
          "gh.security_center.error": e
        )
        GitHub.dogstats.increment("security_center.export.error", tags: ["scope:#{scope.class.to_s.downcase}", "feature:risk", "action:send_email"])
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
        GitHub.dogstats.increment("security_center.risk_export_batched_job.job_status_not_found", tags: all_stats_tags)
        raise RuntimeError.new("JobStatus doesn't exist")
      end

      status
    end

    sig { returns(::Search::Queries::SecurityCenter::RiskQueryParser) }
    memoize def parser
      ::Search::Queries::SecurityCenter::RiskQueryParser.new(query_string)
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      scope = arguments.dig(0, :scope)
      scope_type = scope.class.to_s.downcase
      offset_item_id = arguments.dig(0, :offset_item_id)

      super.merge({
        "gh.security_center.feature_type": "risk",
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
        "Risk export batch job failed",
        "gh.security_center.error": error,
        "gh.security_center.job_action": action,
      )
      GitHub.dogstats.increment(
        "security_center.export.error",
        tags: [
          "scope:#{scope_type}",
          "feature:risk",
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
        security_center_risk_path(scope, query: query_string)
      else
        security_center_risk_enterprise_path(scope, query: query_string)
      end

      SecurityCenterMailer.csv_export_error(
        user:,
        owner: scope,
        redirect_url:,
        feature: "risk",
        query_string:,
        end_date: requested_at.to_date
      ).deliver_now
    end

    sig { params(items: ActiveRecord::Relation, scope: T.any(Organization, Business)).returns(T::Array[::Repository]) }
    def apply_tenant_filter(items, scope)
      request_scope = scope.is_a?(::Business) ? :business : :organization
      filter_tenant_rows(
        RequestScope.new(request_scope, scope, "risk-export"),
        items,
        -> (r) { r.id }
      ).first
    end
  end
end
