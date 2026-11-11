# typed: true
# frozen_string_literal: true

class HydroCustomPatternDryRunNotificationJob < HydroMessageJob
  include GitHub::Memoizer
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

    GitHub.logger.with_named_tags(
      "code.namespace": self.class.name,
      "gh.repo.id": repo_id,
      "gh.queue": queue,
      "gh.payload": message,
    ) do
      unless validate_message(message)
        GitHub.logger.error("invalid payload")
        raise ArgumentError.new("invalid payload")
      end

      repo = T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast

      if repo.nil?
        GitHub.logger.error("repository not found")
        raise SecretScanning::Errors::JobError.new("repository not found")
      end

      if repo.deleted?
        GitHub.logger.info("repo has been deleted, skipping job.")
        return
      end

      business = T.let(nil, T.nilable(Business))
      repo_owner = T.let(nil, T.nilable(User))

      GitHub::CurrentTenant.unscope do
        repo_owner = User.find_by(id: repo.owner_id)
        if repo_owner.nil?
          GitHub.logger.error("repository owner not found")
          raise SecretScanning::Errors::JobError.new("repo owner could not be found")
        end

        if repo_owner.is_a?(Organization)
          business = repo_owner.business
        elsif repo_owner.is_a?(User)
          # We need to use the below instead of repo.owner.enterprise_managed_business.
          # This is because we treat all GHAS users as if they were EMUs for secret scanning purposes, even though they aren't actually enterprise managed in the code.
          ghas_for_emus = ::AdvancedSecurity::Features::User::AdvancedSecurity.new(repo_owner)
          unless ghas_for_emus.feature_available?
            return GitHub.logger.info("Secret scanning not available for user owned repo, skipping job.")
          end
          business = ghas_for_emus.get_business
        end
      end

      GitHub::CurrentTenant.set(business) if GitHub.multi_tenant_enterprise?

      unless SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
        return GitHub.logger.info("Secret scanning not available for repo, skipping job.")
      end

      custom_pattern = message[:custom_pattern]
      result_count = message[:match_count]
      status = message[:dry_run_status]
      actor_id = message[:actor_id]

      actor = User.find_by(id: actor_id)
      if actor.nil?
        GitHub.logger.error("user could not be found")
        raise SecretScanning::Errors::JobError.new("user could not be found")
      end

      scope = custom_pattern[:scope].downcase.to_sym
      pattern_id = custom_pattern[:id]
      pattern_owner = T.let(nil, T.nilable(T.any(Repository, Organization, Business)))

      case scope
      when :repository_scope
        pattern_owner = repo
        unless SecretScanning::Features::Repo::CustomPatterns.new(repo).feature_available?
          return GitHub.logger.info("Custom patterns not available for repo, skipping job")
        end
      when :organization_scope
        pattern_owner = T.cast(repo_owner, Organization)
        return unless pattern_owner.present?
        unless SecretScanning::Features::Org::CustomPatterns.new(pattern_owner).feature_available?
          return GitHub.logger.info("Custom patterns not available for org, skipping job")
        end
      when :business_scope
        pattern_owner = business

        return unless pattern_owner.present?
        unless SecretScanning::Features::Business::CustomPatterns.new(pattern_owner).feature_available?
          return GitHub.logger.info("Custom patterns not available for business, skipping job")
        end
      else
        raise SecretScanning::Errors::JobError.new("unknown custom pattern scope")
      end

      # Notify to websocket channel, so that we can live reload the custom pattern page.
      # This is not critical so fail silently so we can still send emails
      begin
        notify_socket_channel(pattern_id, pattern_owner, scope, status)
      rescue StandardError => e
        GitHub.logger.error("Failed to notify socket channel", { "exception.message" => e.message })
        Failbot.report(e)
      end

      # Emails for org and business-level patterns are handled via job groups, see HydroSecretScanningJobGroupEventProcessorJob
      return unless scope == :repository_scope

      case status
      when :COMPLETED
        if FeatureFlag.vexi.enabled?(:secret_scanning_use_notification_service_for_hydro_jobs, default: false)
          notification_service.deliver_dry_run_summary(pattern_owner, scope, custom_pattern, actor, result_count)
        else
          SecretScanningMailer.custom_pattern_dry_run_scan_summary(pattern_owner, scope, custom_pattern, actor, result_count).deliver_later
        end
        GitHub.logger.info("Queued email to notify completion of custom pattern dry run")
      when :FAILED
        if FeatureFlag.vexi.enabled?(:secret_scanning_use_notification_service_for_hydro_jobs, default: false)
          notification_service.deliver_dry_run_failed(pattern_owner, scope, custom_pattern, actor)
        else
          SecretScanningMailer.custom_pattern_dry_run_scan_failed(pattern_owner, scope, custom_pattern, actor).deliver_later
        end
        GitHub.logger.info("Queued email to notify failure of custom pattern dry run")
      end

      GitHub.dogstats.increment("secret_scanning.custom_pattern_dry_run_notify.processed", tags: ["scope:#{scope}", "status:#{status}"])
      GitHub.logger.info("CustomPatternDryRunNotify message successfully processed")
    end
  end

  private

  sig { params(pattern_id: Integer, owner: T.any(Repository, Organization, Business), scope: Symbol, status: Symbol).void }
  def notify_socket_channel(pattern_id, owner, scope, status)
    data = {
      status: status,
      gid: pattern_id.to_s
    }

    channel = GitHub::WebSocket::Channels.custom_pattern_dry_run_status(owner)
    GitHub::WebSocket.notify_custom_pattern_dry_run_channel(owner, channel, data)
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def validate_message(message)
    required_fields = [
      :dry_run_status,
      :custom_pattern,
      :repository_id,
      :actor_id
    ]

    return false unless required_fields.all? { |field| message[field].present? }
    return false unless message[:repository_id] > 0
    return false unless message[:actor_id] > 0

    return false unless message[:custom_pattern].is_a?(Hash)
    return false unless message[:custom_pattern][:id].present?
    return false unless message[:custom_pattern][:id] > 0
    return false unless message[:custom_pattern][:scope].present?
    true
  end

  memoize def notification_service
    ::SecretScanning::NotificationService.new(caller_namespace: T.must(self.class.name))
  end
end
