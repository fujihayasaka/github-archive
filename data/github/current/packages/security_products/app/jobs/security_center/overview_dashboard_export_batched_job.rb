# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  class OverviewDashboardExportBatchedJob < BatchedJob
    include GitHub::SecurityCenter::LoggingHelper
    include UrlHelpers
    include GitHub::Memoizer
    include GitHub::SecurityCenter::TenantFilteringHelper

    queue_as :security_center_export

    DEFAULT_BATCH_SIZE = 2500

    before_enqueue do |job|
      scope = job.arguments.dig(0, :scope)
      raise ArgumentError.new("scope is required") if scope.nil?

      if scope.is_a?(::Business) && job.arguments.dig(0, :authorized_orgs).nil? && job.arguments.dig(0, :authorized_orgs_by_action).nil?
        raise ArgumentError.new("authorized_orgs or authorized_orgs_by_action is required")
      end

      [
        :user,
        (:user_session if scope.is_a?(::Organization)),
        :security_feature,
        :features_to_process,
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
        security_feature: T::Array[String],
        features_to_process: T::Array[T::Array[String]],
        user_session: UserSession,
        offset_item_id: Integer,
        authorized_orgs: T.nilable(T::Hash[String, T::Array[::Organization]]),
        authorized_orgs_by_action: T.nilable(T::Hash[String, T::Array[::Organization]]),
        is_first_feature: T::Boolean,
        kwargs: T.untyped
      ).returns(T::Array[T::Hash[String, T.untyped]])
    end
    def next_batch(*args, scope:, user:, security_feature:, features_to_process:, user_session:, offset_item_id:, authorized_orgs: nil, authorized_orgs_by_action: nil, is_first_feature: false, **kwargs)
      rel = if scope.is_a?(Organization)
        SecurityOverviewAnalytics::Dashboards::Overview::Queries::BatchedExportData.for_organization(
          organization: scope,
          user:,
          query: Search::Queries::SecurityCenter::QueryParser.new(query_string),
          start_date:,
          end_date:,
          security_features: security_feature,
          user_session:,
        ).perform
      else
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

        SecurityOverviewAnalytics::Dashboards::Overview::Queries::BatchedExportData.for_business(
          business: scope,
          user:,
          query: Search::Queries::SecurityCenter::QueryParser.new(query_string),
          start_date:,
          end_date:,
          security_features: security_feature,
          user_session:,
          authorized_orgs_by_feature:,
        ).perform
      end

      sql = rel
        .where(id: (offset_item_id + 1)..)
        .order(:id)
        .limit(batch_size)
        .to_sql

      tags = ["inner_query:#{SecurityCenter::FeatureFlagHelper.overview_export_use_inner_query?(scope, user)}"]
      fields_to_values = GitHub.dogstats.distribution_time("security_overview_analytics.dashboards.overview.batched_export_job_query_data.perform.dist", tags:) do
        ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql).map(&:to_h)
      end

      if fields_to_values.size >= batch_size
        @next_batch_id = T.let(fields_to_values.map { |b| b["id"] }.max, T.nilable(Integer))
      end

      if fields_to_values.present?
        # Apply tenant filter
        repo_ids = fields_to_values.map { |row| row["repository_id"] }.uniq
        allowed_repos = Repositories::Public.load_repositories(repo_ids)
          .preload(:owner)
          .then { |rel| apply_tenant_filter(rel, scope) }
        allowed_repos_by_id = allowed_repos.index_by(&:id)
        allowed_repo_ids = allowed_repos_by_id.keys
        fields_to_values = fields_to_values.filter { |row| allowed_repo_ids.include? row["repository_id"] }

        team_id_to_slug = if scope.is_a?(Organization)
          scope
            .visible_teams_for(user, fields: [:id, :slug])
            .pluck(:id, :slug)
            .to_h
        else
          allowed_repos
            .map(&:owner)
            .uniq
            .flat_map do |owner|
              next [] unless owner.is_a?(Organization)
              owner
                .visible_teams_for(user, fields: [:id, :slug])
                .pluck(:id, :slug)
            end
            .to_h
        end

        topic_names_by_repository_id = SecurityCenter::Export::DataQuery.get_topics_by_repository_id(allowed_repo_ids)
        teams_by_repository_id = SecurityCenter::Export::DataQuery.get_teams_by_repository_id(allowed_repo_ids, team_id_to_slug, scope, 1)

        property_values_by_repo = CustomProperties::Public.repo_properties(allowed_repos.select { |r| r.owner&.organization? }, :effective)
        props_by_repo_id = property_values_by_repo.transform_keys(&:id)

        fields_to_values.each do |row|
          # put existing data in the correct format
          row["repository_nwo"] = allowed_repos_by_id[row["repository_id"]].name_with_display_owner
          row["visibility"] = SecurityOverviewAnalytics::Repository.visibilities.key(row["visibility"])
          row["archived"] = allowed_repos_by_id[row["repository_id"]].archived?
          row["alert_severity"] = row["alert_severity"] == "moderate" ? "medium" : row["alert_severity"]&.downcase
          row["alert_bypassed"] = ActiveModel::Type::Boolean.new.cast(row["alert_bypassed"]).to_s if row["alert_bypassed"].present?
          if row["alert_resolution"]
            mapping = case row["tool"]
            when "dependabot"
              SecurityOverviewAnalytics::DependabotAlertRevision::RESOLUTIONS_MAPPING
            when "secret-scanning"
              SecurityOverviewAnalytics::SecretScanningAlertRevision::RESOLUTIONS_MAPPING
            else
              SecurityOverviewAnalytics::CodeScanningAlertRevision::RESOLUTIONS_MAPPING
            end

            row["alert_resolution"] = mapping.select do |resolution_name, resolution_values|
              resolution_name if resolution_values.include?(row["alert_resolution"])
            end.keys.first
          end
          if row["alert_validity"].present?
            row["alert_validity"] = SecurityOverviewAnalytics::SecretScanningAlertRevision::VALIDITIES_MAPPING.select do |validity_name, validity_values|
              validity_name if validity_values.include?(row["alert_validity"])
            end.keys.first
          end

          # add missing data
          row["codeql_tool"] = row["tool"] == "CodeQL" ? row["rule_sarif_identifier"] : nil
          row["third_party_tool"] = row["tool"] == "CodeQL" ? nil : row["rule_sarif_identifier"]
          row["teams"] = teams_by_repository_id[row["repository_id"]] || []
          row["repo_properties"] = props_by_repo_id[row["repository_id"]]&.with_indifferent_access || []
          row["repo_topics"] = topic_names_by_repository_id[row["repository_id"]] || []
        end
      end

      fields_to_values || []
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: "next_batch")
    end

    sig do
      params(
        batch: T::Array[{}],
        args: T.untyped,
        scope: T.any(Organization, Business),
        offset_item_id: Integer,
        is_first_feature: T::Boolean,
        kwargs: T.untyped
      ).void
    end
    def process_batch(batch, *args, scope:, offset_item_id:, is_first_feature: false, **kwargs)
      # At the org-level, get the headers for custom properties.
      # We need to pass this (rather than using the first row of data) to handle the case where a query doesn't have data.
      if scope.is_a?(Organization)
        manager = CustomProperties::Public.definitions_manager(scope)
        custom_properties = manager.get_definitions.map(&:property_name)
      end

      csv = OverviewDashboard::ExportCsvGenerator.generate(batch, custom_properties, is_first_feature && offset_item_id.zero?)

      storage_service = Export::BlobStorageService.get

      if is_first_feature && offset_item_id.zero?
        storage_service.create(export_id)
      end

      return if csv.empty?
      storage_service.store(export_id, csv, "overview_dashboard")
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: "process_batch")
    end

    sig do
      params(
        batch: T::Array[{}],
        args: T.untyped,
        scope: T.any(Organization, Business),
        user: User,
        security_feature: T::Array[String],
        features_to_process: T::Array[T::Array[String]],
        user_session: UserSession,
        offset_item_id: Integer,
        authorized_orgs: T.nilable(T::Hash[String, T::Array[::Organization]]),
        authorized_orgs_by_action: T.nilable(T::Hash[String, T::Array[::Organization]]),
        kwargs: T.untyped
      ).void
    end
    def finalize_batch(batch, *args, scope:, user:, security_feature:, features_to_process:, user_session:, offset_item_id:, authorized_orgs: nil, authorized_orgs_by_action: nil, **kwargs)
      return if has_next_batch?(batch)

      GitHub.logger.info(
        "Finalizing batches for current feature",
        "code.namespace": self.class.name,
        "code.function": __method__
      )

      if features_to_process.empty? # This is the final job; record the JobStatus as success! and email user
        job_status.success!

        csv_url = if scope.is_a?(Organization)
          security_center_overview_dashboard_get_export_path(scope, export_id:, format: :csv)
        else
          enterprise_security_center_overview_dashboard_export_path(scope, export_id:, format: :csv)
        end

        begin
          SecurityCenterMailer.csv_export_ready(
            user:,
            owner: scope,
            csv_url:,
            feature: "security overview",
            query_string:,
            end_date:,
            row_type: "alerts on default branch",
            file_expiration: ::SecurityCenter::Export::BlobStorageService::FILE_EXPIRY.from_now,
          ).deliver_now
        rescue => e # rubocop:disable Lint/GenericRescue
          Failbot.report(e)
          log_warn(
            "Overview Dashboard export failed to send an email",
            "gh.security_center.error": e
          )
          GitHub.dogstats.increment("security_center.export.error", tags: ["scope:#{scope.class.to_s.downcase}", "feature:overview_dashboard", "action:send_email"])
        end
      else # We're through one feature; queue the next feature
        job = ::SecurityCenter::OverviewDashboardExportBatchedJob.perform_later(
          scope:,
          user:,
          query_string:,
          start_date:,
          end_date:,
          security_feature: features_to_process.pop,
          features_to_process: features_to_process,
          requested_at:,
          is_first_feature: false,
          user_session:,
          authorized_orgs:,
          authorized_orgs_by_action:,
          offset_item_id: 0,
          export_id:
        )

        raise RuntimeError.new("Failed to create export job") unless job
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
      @next_batch_id
    end

    sig do
      override
        .params(batch: T::Array[{}], options: T.untyped)
        .returns(T::Boolean)
    end
    def has_next_batch?(batch, **options)
      @next_batch_id.present?
    end

    sig { returns(Integer) }
    memoize def batch_size
      scope = arguments.dig(0, :scope)
      return DEFAULT_BATCH_SIZE if scope.nil?
      return DEFAULT_BATCH_SIZE unless scope.feature_enabled?(:security_center_overview_dashboard_export_batch_size_scale_factor)

      scale_factor = GitHub.flipper[:security_center_overview_dashboard_export_batch_size_scale_factor].percentage_of_actors_value
      scale_factor == 0 ? DEFAULT_BATCH_SIZE : (scale_factor * 100)
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

    sig { returns(Date) }
    def start_date
      T.must(job_status.start_date).to_date
    end

    sig { returns(Date) }
    def end_date
      T.must(job_status.end_date).to_date
    end

    sig { returns(String) }
    def export_id
      self.arguments.dig(0, :export_id)
    end

    sig { returns(Export::JobStatus) }
    memoize def job_status
      status = ::SecurityCenter::Export::JobStatus.find(export_id)
      if status.nil?
        GitHub.dogstats.increment("security_center.overview_dashboard_export_batched_job.job_status_not_found", tags: all_stats_tags)
        raise RuntimeError.new("JobStatus doesn't exist")
      end

      status
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      scope = arguments.dig(0, :scope)
      scope_type = scope.class.to_s.downcase
      offset_item_id = arguments.dig(0, :offset_item_id)
      security_feature = arguments.dig(0, :security_feature)
      features_to_process = arguments.dig(0, :features_to_process)

      super.merge({
        "gh.security_center.feature_type": "overview_dashboard",
        "gh.security_center.search.query": query_string,
        "gh.security_center.scope": scope_type,
        "gh.security_center.scope_id": scope.id,
        "gh.security_center.scope_login": scope.display_login,
        "gh.security_center.batch_size": batch_size,
        "gh.security_center.offset_item_id": offset_item_id,
        "gh.security_center.current_feature": security_feature,
        "gh.security_center.remaining_feautres": features_to_process,
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      }).merge(logging_context)
    end

    sig { params(error: StandardError, action: String).void }
    def report_job_error(error, action:)
      scope = arguments.dig(0, :scope)
      scope_type = scope.class.to_s.downcase

      log_warn(
        "Overview Dashboard export batch job failed",
        "gh.security_center.error": error,
        "gh.security_center.job_action": action,
      )
      GitHub.dogstats.increment(
        "security_center.export.error",
        tags: [
          "scope:#{scope_type}",
          "feature:overview_dashboard",
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
      owner = self.arguments.dig(0, :scope)

      SecurityCenterMailer.csv_export_error(
        user:,
        owner:,
        redirect_url: security_center_overview_dashboard_path(owner, query: query_string),
        feature: "security overview",
        query_string:,
        end_date:
      ).deliver_now
    end

    sig { params(items: ActiveRecord::Relation, scope: T.any(Organization, Business)).returns(T::Array[::Repository]) }
    def apply_tenant_filter(items, scope)
      request_scope = scope.is_a?(::Business) ? :business : :organization
      filter_tenant_rows(
        RequestScope.new(request_scope, scope, "overview-dashboard-export"),
        items,
        -> (r) { r.id }
      ).first
    end
  end
end
