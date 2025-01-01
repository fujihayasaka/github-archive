# typed: true
# frozen_string_literal: true

class HydroCustomPatternDryRunNotificationJob < HydroMessageJob
  queue_as :hydro_custom_pattern_dry_run_notification

  retry_on_dirty_exit
  retry_on *T.unsafe(Resiliency::Response::UnavailableExceptions)
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  # Processes hydro messages for custom pattern dry run updates,
  # and uses them to send email notifications to the user, and notify
  # the web socket for live updates.
  #
  # Returns nothing
  def perform
    repo_id = message[:repository_id]
    return unless repo_id.present?

    repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: repo_id)
    end

    if repo.nil?
      Failbot.report(StandardError.new("repo with id could not be found"), user_id: repo_id)
      return
    end

    if repo.owner.is_a?(Organization)
      business = T.must(repo.owner).business
    elsif repo.owner.is_a?(User)
      # We need to use the below instead of repo.owner.enterprise_managed_business.
      # This is because we treat all GHAS users as if they were EMUs for secret scanning purposes, even though they aren't actually enterprise managed in the code.
      ghas_for_emus = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(T.must(repo.owner))
      return unless ghas_for_emus.feature_available?
      business = ghas_for_emus.get_business
    end

    current_tenant = GitHub.multi_tenant_enterprise? ? GitHub::CurrentTenant.unscope { business } : nil

    GitHub::CurrentTenant.set(current_tenant) do
      unless SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        GitHub.logger.info(
          "Secret scanning not available for repo",
          {
          "code.function" => "perform",
          "code.namespace" => self.class.name,
          "gh.repo.id" => repo.id
          }
        )
      end

      custom_pattern = message[:custom_pattern]
      return unless custom_pattern.present?

      result_count = message[:match_count]
      status = message[:dry_run_status]

      created_by_id = custom_pattern[:created_by_id]
      return if created_by_id == 0
      created_by = User.find_by(id: created_by_id)
      if created_by.nil?
        Failbot.report(StandardError.new("user could not be found"), user_id: created_by)
        return
      end

      scope = custom_pattern[:scope].downcase.to_sym
      pattern_id = custom_pattern[:id]
      owner = nil

      logger_opts = {
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.notifications.pattern_id" => pattern_id,
        "gh.notifications.scope" => scope,
        "gh.notifications.dry_run_status" => status
      }

      case scope
      when :repository_scope
        owner = repo
        unless SecretScanning::Features::Repo::CustomPatterns.new(repo).feature_available?
          GitHub.logger.info("Custom patterns not available for repo", logger_opts)
          return
        end
      when :organization_scope
        owner = T.cast(repo.owner, Organization)
        return unless owner.present?
        unless SecretScanning::Features::Org::CustomPatterns.new(owner).feature_available?
          GitHub.logger.info("Custom patterns not available for org", logger_opts)
          return
        end
      when :business_scope
        owner = business

        return unless owner.present?
        unless SecretScanning::Features::Business::CustomPatterns.new(owner).feature_available?
          GitHub.logger.info("Custom patterns not available for business", logger_opts)
          return
        end
      else
        return
      end

      logger_opts.merge({ "gh.notifications.owner.id" => owner.id })

      # Notify to websocket channel, so that we can live reload the custom pattern page.
      notify_socket_channel(pattern_id, owner, scope, status)

      # Emails for org and business-level patterns are pending implementation of job groups in token scanning service
      return unless scope == :repository_scope

      case status
      when :COMPLETED
        SecretScanningMailer.custom_pattern_dry_run_scan_summary(owner, scope, custom_pattern, created_by, result_count).deliver_later
        GitHub.logger.info("Queued email to notify completion of custom pattern dry run", logger_opts)
      when :FAILED
        SecretScanningMailer.custom_pattern_dry_run_scan_failed(owner, scope, custom_pattern, created_by).deliver_later
        GitHub.logger.info("Queued email to notify failure of custom pattern dry run", logger_opts)
      end

      GitHub.dogstats.increment("secret_scanning.custom_pattern_dry_run_notify.processed", tags: ["scope:#{scope}", "status:#{status}, pattern_id:#{pattern_id}"])
      GitHub.logger.info("CustomPatternDryRunNotify message processed", logger_opts)
    end
  end

  def notify_socket_channel(pattern_id, owner, scope, status)
    data = {
      status: status,
      gid: pattern_id.to_s
    }

    channel = GitHub::WebSocket::Channels.custom_pattern_dry_run_status(owner)
    GitHub::WebSocket.notify_custom_pattern_dry_run_channel(owner, channel, data)
    GitHub.logger.info("Notified socket channel successfully", {
      "code.namespace" => "HydroCustomPatternDryRunNotificationJob",
      "code.function" => "notify_socket_channel",
      "gh.notifications.pattern_id" => pattern_id,
      "gh.notifications.owner.id" => owner.id,
      "gh.notifications.scope" => scope,
      "gh.notifications.dry_run_status" => status
    })
  end
end
