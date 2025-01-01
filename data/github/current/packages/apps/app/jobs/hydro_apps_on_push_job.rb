# typed: true
# frozen_string_literal: true

class HydroAppsOnPushJob < Repositories::PushHydroMessageJob
  queue_as :hydro_apps_on_push

  class AppsSpokesExhaustedError < StandardError; end

  # We don't want to deliver web hooks after 1 hour (7 retries = ~40m wait time)
  retry_on(*(Orchestration::RETRYABLE_ERRORS + [Repositories::PushHydroMessageJob::RepositoryNotFound, AppsSpokesExhaustedError]), delay: :polynomially_longer, max_retries: 7)

  def perform
    if total_branch_count > Pushes::CommitsHelper::LARGE_BRANCH_COUNT_THRESHOLD
      GitHub.logger.info(
        "Skipping HydroAppsOnPushJob for large push.",
        "ref_updates.count": total_ref_count,
        "code.namespace": "HydroAppsOnPushJob",
        "gh.request_id": request_id,
        "gh.repo.id": repository.id,
      )

      GitHub.dogstats.increment("hydro_apps_on_push_job.large_push_skip")

      # don't dispatch hooks (which trigger actions) or install apps for a very large push
      return
    end

    deliver_webhooks unless retries(AppsSpokesExhaustedError.new) > 0

    begin
      install_apps
    rescue SpokesAPI::ResourceExhausted => e
      err = AppsSpokesExhaustedError.new(e.message)
      err.set_backtrace(e.backtrace)
      raise err
    end
  end

  private

  def deliver_webhooks
    applicable_refs = ref_updates.reject { |ref_update| !ref_update.branch_or_tag? }
    applicable_refs.each do |ref_update|
      payload = {
        repo: repository,
        ref: ref_update.ref,
        before: ref_update.before,
        after: ref_update.after,
        pusher: pusher,
        triggered_at: Time.now,
        pushed_at: pushed_at
      }
      event = Hook::Event::PushEvent.new(payload)
      delivery_system = Hook::DeliverySystem.new(event)
      delivery_system.generate_push_event_hookshot_payloads
      delivery_system.deliver_push_event_later(merge: merge_method&.to_sym == :merge)
    end
  end

  def install_apps
    ref_updates_for_app_installation.each do |push|
      AutomaticAppInstallation.trigger(
        type: :file_added,
        originator: push,
        actor: pusher,
      )
    end
  end

  memoize def pushes
    applicable_refs = ref_updates.reject do |ref_update|
      !ref_update.branch_or_tag? || (ref_update.ref_is_tag? && !ref_update.deleted?)
    end

    applicable_refs
  end

  # A list of the ref updates that should be examined to check for changes to config files that will prompt app installations.
  # This list may contain different updates than the ref_updates list, or may be empty, depending on the type of app installation that is needed.
  memoize def ref_updates_for_app_installation
    updates = if needs_actions? || needs_actions_lab? || needs_additional_app?
      # for these apps, we need to look at all the changes for the config files.
      ref_updates
    elsif needs_dependabot?
      # dependabot only needs to be installed if the default branch is getting updated.
      [push_includes_default_branch?].compact
    else
      # if we don't need to install any apps, don't load anything.
      []
    end

    applicable_refs = updates.reject do |ref_update|
      !ref_update.branch_or_tag? || (ref_update.ref_is_tag? && !ref_update.deleted?)
    end
  end

  memoize def apps_to_auto_install
    IntegrationInstallTrigger.by_install_type(:file_added).map(&:integration)
  end

  memoize def apps_already_installed
    app_ids_installed_for_repo = IntegrationInstallation.with_repository(repository).where(integration: apps_to_auto_install).pluck(:integration_id)
    apps_to_auto_install.filter { |app| app_ids_installed_for_repo.include?(app.id) }
  end

  def needs_dependabot?
    # dependabot only needs to be installed if the *default* branch is getting dependabot file updates
    return false unless push_includes_default_branch?
    apps_to_auto_install.include?(GitHub.dependabot_github_app) && apps_already_installed.none?(GitHub.dependabot_github_app)
  end

  def needs_actions?
    apps_to_auto_install.include?(GitHub.launch_github_app) && apps_already_installed.none?(GitHub.launch_github_app)
  end

  def needs_actions_lab?
    return unless repository.feature_enabled?(:launch_lab) || repository.owner.feature_enabled?(:launch_lab)

    apps_to_auto_install.include?(GitHub.launch_lab_github_app) && apps_already_installed.none?(GitHub.launch_lab_github_app)
  end

  # Whether there's a file_added installation handler for anything other than actions, actions-lab, or dependabot.
  # It's unlikely that this will ever happen, but it's technically possible that we could set up a new app for automatic installation this way.
  def needs_additional_app?
    # these apps are handled separately
    apps_needed = apps_to_auto_install - [GitHub.launch_github_app, GitHub.launch_lab_github_app, GitHub.dependabot_github_app]
    (apps_needed - apps_already_installed).any?
  end
end
