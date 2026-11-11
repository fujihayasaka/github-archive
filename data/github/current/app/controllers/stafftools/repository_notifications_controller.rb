# typed: true
# frozen_string_literal: true

class Stafftools::RepositoryNotificationsController < StafftoolsController
  before_action :ensure_repo_exists

  layout "layouts/stafftools/repository/collaboration"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  FEATURES = [
    :notifications_stafftools_edit_repo_email_hook,
  ]

  preload_features FEATURES

  SLOW_QUERY_THRESHOLD_MS = 2_000
  AUDIT_LOG_TIMEOUT_SECONDS = 2
  SHORT_TIMEOUT_FEATURE_FLAG = :notifications_stafftools_repo_settings_audit_log_short_timeout

  def show
    audit_log_query = [
      "data.name:Email",
      "data.hook_type:repo",
      "repo_id:#{current_repository.id}",
    ].join(" AND ")

    if GitHub.driftwood_ade_queries_enabled?
      audit_log_query = <<~KQL
        webevents
        | where data.name == "Email" and data.hook_type == "repo" and repo_id == #{current_repository.id}
      KQL
    end

    audit_log_data = fetch_audit_log_teaser_with_instrumentation(audit_log_query)

    view = Stafftools::RepositoryViews::RepositoryNotificationsView.new(
      current_repository: current_repository,
      audit_log_data: audit_log_data,
    )

    render "stafftools/repository_notifications/show", locals: {
      view: view,
    }
  end

  def update
    return redirect_to(action: :show) unless FeatureFlag.vexi.enabled?(:notifications_stafftools_edit_repo_email_hook, current_user, default: false)

    if hook&.update(hook_params)
      flash[:notice] = "Repository notification settings updated"

      redirect_to action: :show
    else
      flash.now[:error] = hook&.errors&.full_messages&.to_sentence || "The notification settings couldn't be found"
      show
    end
  end

  def destroy
    return redirect_to(action: :show) unless FeatureFlag.vexi.enabled?(:notifications_stafftools_edit_repo_email_hook, current_user, default: false)

    if hook&.destroy
      flash[:notice] = "Repository notification settings cleared."
    else
      flash[:error] = "There was a problem deleting your repository notification settings."
    end

    redirect_to action: :show
  end

  private

  memoize def hook
    Hook.email_hooks_for_target(current_repository).first
  end

  def hook_params
    params.require(:hook).permit(:active, { config_attributes: [:address] })
  end

  def fetch_audit_log_teaser_with_instrumentation(query)
    status = "success"
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    short_timeout_client = short_timeout_client_for_audit_log
    result = fetch_audit_log_teaser(query, client: short_timeout_client)

    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round
    if duration_ms > SLOW_QUERY_THRESHOLD_MS
      GitHub.logger.warn(
        "Slow Driftwood audit log query in stafftools repo notifications",
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        "gh.audit_log.duration_ms" => duration_ms,
        "gh.repo.id" => current_repository.id,
        "gh.audit_log.result_count" => result[:logs].size,
      )
    end

    result
  rescue Faraday::TimeoutError => e
    # Only swallow the timeout gracefully when the short-timeout client is in use
    # (i.e., the feature flag is enabled). Otherwise, preserve the previous Failbot
    # reporting behavior so disabling the flag fully restores the old behavior.
    if short_timeout_client
      status = "timed_out"
      GitHub.logger.warn(
        "Driftwood audit log query timed out",
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        "gh.audit_log.timeout_seconds" => AUDIT_LOG_TIMEOUT_SECONDS,
        "gh.repo.id" => current_repository.id,
      )
    else
      status = "error"
      Failbot.report(e,
        app: "stafftools-repo-notifications",
        "gh.repo.id": current_repository.id,
      )
    end
    { query: query, more_results: false, logs: [] }
  rescue Driftwood::TwirpUtil::InvalidArgumentError => e
    status = "invalid_argument"
    GitHub.logger.error(
      "Driftwood audit log query returned invalid argument error",
      "code.namespace" => self.class.name,
      "code.function" => __method__.to_s,
      "gh.repo.id" => current_repository.id,
      :exception => e,
    )
    { query: query, more_results: false, logs: [] }
  rescue Driftwood::TwirpUtil::RateLimitedError
    status = "rate_limited"
    GitHub.logger.warn(
      "Driftwood audit log query was rate limited",
      "code.namespace" => self.class.name,
      "code.function" => __method__.to_s,
      "gh.repo.id" => current_repository.id,
    )
    { query: query, more_results: false, logs: [] }
  rescue Driftwood::TwirpUtil::Error, Faraday::Error, Twirp::Error => e
    status = "error"
    Failbot.report(e,
      app: "stafftools-repo-notifications",
      "gh.repo.id": current_repository.id,
    )
    { query: query, more_results: false, logs: [] }
  ensure
    duration_s = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start if start
    if duration_s
      GitHub.dogstats.timing("stafftools.repo_notifications.audit_log_teaser.duration", duration_s * 1000,
        tags: ["status:#{status}"],
      )
    end
  end

  def short_timeout_client_for_audit_log
    return nil unless FeatureFlag.vexi.enabled?(
      SHORT_TIMEOUT_FEATURE_FLAG,
      current_repository,
      default: false,
    )

    @short_timeout_client_for_audit_log ||= ::Driftwood::V1::Client.new(
      GitHub.driftwood_host,
      faraday_options: {
        timeout: AUDIT_LOG_TIMEOUT_SECONDS,
        open_timeout: AUDIT_LOG_TIMEOUT_SECONDS,
      },
      hmac_key: GitHub.driftwood_hmac_key,
      faraday_middleware: [[GitHub::FaradayMiddleware::DriftwoodRequestID]],
    )
  end
end
