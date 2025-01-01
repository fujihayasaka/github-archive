# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  class OverviewDashboardExportBatchedJob < BatchedJob
    extend T::Sig

    include GitHub::SecurityCenter::LoggingHelper
    include UrlHelpers
    include GitHub::Memoizer

    queue_as :security_center_export

    DEFAULT_BATCH_SIZE = 2500

    before_perform do |job|
      is_first_feature = job.arguments.dig(0, :is_first_feature)
      offset_item_id = job.arguments.dig(0, :offset_item_id)

      next unless is_first_feature && offset_item_id.zero?

      status = check_job_status
      status.started!
    end

    sig do
      params(
        args: T.untyped,
        scope: T.any(Organization, Business),
        user: User,
        query_string: String,
        start_date: Date,
        end_date: Date,
        allowed_repo_ids_by_feature: T.nilable(T::Hash[String, T::Array[Integer]]),
        security_feature: T::Array[String],
        features_to_process: T::Array[T::Array[String]],
        requested_at: Time,
        user_session: UserSession,
        offset_item_id: Integer,
        is_first_feature: T::Boolean,
        kwargs: T.untyped
      ).returns(T::Array[T::Hash[String, T.untyped]])
    end
    def next_batch(*args, scope:, user:, query_string:, start_date:, end_date:, allowed_repo_ids_by_feature:, security_feature:, features_to_process:, requested_at:, user_session:, offset_item_id:, is_first_feature: false, **kwargs)
      query = Search::Queries::SecurityCenter::QueryParser.new(query_string)

      repos_filterer = ::SecurityOverviewAnalytics::Dashboards::OrgReposFilterer.new(
        allowed_repo_ids_by_feature:,
        organization: T.cast(scope, Organization),
        query: Search::Queries::SecurityCenter::QueryParser.new(query_string),
        user:,
        user_session:
      )

      alerts_filterer = ::SecurityOverviewAnalytics::Dashboards::AlertsFilterer.new(
        query: Search::Queries::SecurityCenter::QueryParser.new(query_string),
        scope: scope,
        user: user
      )

      # Note: initializing directly instead of using for_organization and for_business factory helpers here because
      # we need to run the query for specific security features, not all the features in the user_query.
      rel = SecurityOverviewAnalytics::Dashboards::Overview::Queries::BatchedExportData.new(
        user:,
        query_parser: query,
        alerts_filterer:,
        repos_filterer:,
        scope:,
        start_date:,
        end_date:,
        security_features: security_feature,
        authorized_orgs: nil, # TODO: update once we implement business-level export
        user_session:,
        return_alert_count: false,
        is_open_selected: true
      ).perform

      sql = rel
        .where("id > ?", offset_item_id)
        .order(:id)
        .limit(batch_size)
        .to_sql

      fields_to_values = ApplicationRecord::SecurityOverviewAnalytics.connection.select_all(sql).map(&:to_h)

      if fields_to_values.present?
        # TODO make this work at the business level
        team_id_to_slug = T.cast(scope, Organization)
          .visible_teams_for(user, fields: [:id, :slug])
          .pluck(:id, :slug)
          .to_h

        repo_ids = fields_to_values.map { |row| row["repository_id"] }.uniq
        topic_names_by_repository_id = SecurityCenter::Export::DataQuery.get_topics_by_repository_id(repo_ids)
        teams_by_repository_id = SecurityCenter::Export::DataQuery.get_teams_by_repository_id(repo_ids, team_id_to_slug, scope, 1)

        repos = ::Repository.where(id: repo_ids)
        property_values_by_repo = CustomProperties::Public.repo_properties(repos, :effective)
        props_by_repo_id = property_values_by_repo.transform_keys(&:id)

        fields_to_values.each do |row|
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
        user: User,
        query_string: String,
        start_date: Date,
        end_date: Date,
        requested_at: Time,
        offset_item_id: Integer,
        is_first_feature: T::Boolean,
        kwargs: T.untyped
      ).void
    end
    def process_batch(batch, *args, scope:, user:, query_string:, start_date:, end_date:, requested_at:, offset_item_id:, is_first_feature: false,  **kwargs)
      csv = OverviewDashboard::ExportCsvGenerator.generate(batch, is_first_feature && offset_item_id.zero?)

      storage_service = Export::BlobStorageService.get(scope)

      if is_first_feature && offset_item_id.zero?
        storage_service.create(get_token, true)
      end

      return if csv.empty?
      storage_service.store(get_token, csv, "overview_dashboard", true)
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: "process_batch")
    end

    sig do
      params(
        batch: T::Array[{}],
        args: T.untyped,
        scope: T.any(Organization, Business),
        user: User,
        query_string: String,
        start_date: Date,
        end_date: Date,
        allowed_repo_ids_by_feature: T.nilable(T::Hash[String, T::Array[Integer]]),
        requested_at: Time,
        security_feature: T::Array[String],
        features_to_process: T::Array[T::Array[String]],
        user_session: UserSession,
        offset_item_id: Integer,
        kwargs: T.untyped
      ).void
    end
    def finalize_batch(batch, *args, scope:, user:, query_string:, start_date:, end_date:, allowed_repo_ids_by_feature:, requested_at:, security_feature:, features_to_process:, user_session:, offset_item_id:, **kwargs)
      return if has_next_batch?(batch)

      if features_to_process.empty? # This is the final job; record the JobStatus as success! and email user
        status = check_job_status
        status.success!

        begin
          SecurityCenterMailer.csv_export_ready(
            user:,
            owner: scope,
            csv_url: security_center_overview_dashboard_get_export_path(export_id: get_token, org: scope, format: :csv),
            feature: "security overview",
            query_string:,
            end_date:,
            row_type: "alerts"
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
          allowed_repo_ids_by_feature:,
          security_feature: features_to_process.pop,
          features_to_process: features_to_process,
          requested_at:,
          is_first_feature: false,
          user_session:,
          offset_item_id: 0
        )

        raise RuntimeError.new("Failed to create export job") unless job
      end
    rescue => e # rubocop:disable Lint/GenericRescue
      report_job_error(e, action: "finalize_batch")
    end

    sig { params(batch: T::Array[{}], args: T.untyped, options: T.untyped).returns(Integer) }
    def next_batch_offset_item_id(batch, *args, **options)
      batch.map { |b| b["id"] }.max
    end

    sig { params(batch: T::Array[{}], options: T.untyped).returns(T::Boolean) }
    def has_next_batch?(batch, **options)
      batch.size >= batch_size
    end

    sig { returns(Integer) }
    memoize def batch_size
      scope = arguments.dig(0, :scope)
      return DEFAULT_BATCH_SIZE if scope.nil?
      return DEFAULT_BATCH_SIZE unless scope.feature_enabled?(:security_center_overview_dashboard_export_batch_size_scale_factor)

      scale_factor = GitHub.flipper[:security_center_overview_dashboard_export_batch_size_scale_factor].percentage_of_actors_value
      scale_factor == 0 ? DEFAULT_BATCH_SIZE : (scale_factor * 100)
    end

    sig { returns(Export::JobStatus) }
    def check_job_status
      status = Export::JobStatus.find(get_token)
      if status.nil?
        GitHub.dogstats.increment("security_center.overview_dashboard_export_batched_job.job_status_not_found", tags: all_stats_tags)
        raise RuntimeError.new("JobStatus doesn't exist")
      end

      status
    end

    sig { returns(String) }
    memoize def get_token
      parser = ::Search::Queries::SecurityCenter::QueryParser.new(self.arguments.dig(0, :query_string))

      Export::TokenGenerator.create_token(
        user: self.arguments.dig(0, :user),
        scope: self.arguments.dig(0, :scope),
        query: parser.canonicalize,
        feature_type: "overview_dashboard",
        requested_at: self.arguments.dig(0, :requested_at),
        start_date: self.arguments.dig(0, :start_date),
        end_date: self.arguments.dig(0, :end_date),
      )
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.security_center.feature_type": "overview_dashboard",
        "gh.security_center.search.query": arguments.dig(0, :query_string),
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
      log_warn(
        "Overview Dashboard export batch job failed",
        "gh.security_center.error": error,
        "gh.security_center.job_action": action,
        "gh.security_center.batch_size": batch_size,
      )
      GitHub.dogstats.increment(
        "security_center.export.error",
        tags: [
          "scope:#{self.arguments.dig(0, :scope).class.to_s.downcase}",
          "feature:overview_dashboard",
          "action:#{action}"
          ]
        )

      send_error_email
      status = check_job_status
      status.error!("We couldn't generate your report. Please try again later. If the problem persists, please contact support.", ttl: 10.days)

      raise error
    end

    sig { void }
    def send_error_email
      user = self.arguments.dig(0, :user)
      owner = self.arguments.dig(0, :scope)
      end_date = self.arguments.dig(0, :end_date)
      query = self.arguments.dig(0, :query_string)

      SecurityCenterMailer.csv_export_error(
        user:,
        owner:,
        redirect_url: security_center_overview_dashboard_path(owner, query:),
        feature: "security overview",
        query_string: query,
        end_date:
      ).deliver_now
    end
  end
end
