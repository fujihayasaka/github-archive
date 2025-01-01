# typed: true
# frozen_string_literal: true

module SecurityAnalysisSettingsHelper
  extend T::Sig
  include UrlHelper
  include ActionView::Helpers::TextHelper
  include GitHub::Memoizer
  include EscapeHelper

  # These definitions pacify Sorbet, which flags them because they're defined in
  # controllers, then used by controllers and views.
  def owner; super; end
  def current_repository; super; end
  def current_user; super; end
  def repo_count; super; end
  def private_repo_count; super; end

  PUSH_PROTECTION_CUSTOM_MSG_MAX_SIZE = 150

  def push_protection_custom_message_valid(message)
    if message.blank?
      return { valid: false, reason: :blank }
    end
    safe_link = safe_uri(message)
    if safe_link.nil? || safe_link.empty?
      return { valid: false, reason: :not_url }
    end
    if safe_link.size > PUSH_PROTECTION_CUSTOM_MSG_MAX_SIZE
      return { valid: false, reason: :size }
    end
    { valid: true, reason: nil }
  end

  # Provides link to manage repo-level security settings
  def security_analysis_settings_path(repository)
    repo_settings_path = edit_repository_path(repository)
    "#{repo_settings_path}/security_analysis"
  end

  # Return a message to be shown describing why advanced security cannot be enabled
  # for a particular target. The target can be a repository, an organization, or a business.
  # Must pass in the number of seats that would be used by enabling GHAS.
  #
  # Should only be called in cases where enabling GHAS is indeed blocked by the seat
  # count, otherwise the message returned by this method will be blank.
  def advanced_security_blocked_by_seat_count_message(target:, seats_needed:)
    case target
    when Repository
      owner = target.owner
      kind = "repository"
    when Organization
      owner = target
      kind = "organization"
    when Business
      owner = target
      kind = "enterprise"
    else
      owner = target
      kind = target.class.name
    end
    license = owner.advanced_security_license
    available = license.seats - license.consumed_seats
    name = owner.advanced_security_license.billable_entity.name
    ghas = "GitHub Advanced Security"

    return "" if seats_needed <= available

    # If the user is trying to enable Advanced Secrity on everything in the billable entity we can use the word "all".
    # If they're only enabling Advanced Security on a subset of repositories, we need to use the word "additional" as some committers may already be allocated licenses.
    all_or_additional = owner.advanced_security_license.billable_entity == target ? "all" : "additional"

    # there are no additional unique committers but the customer is currently over the seat count
    return "#{name} is using #{available.abs} more #{ghas} #{available.abs > 1 ? "licenses" : "license"} than they have purchased." if available < 0 && seats_needed == 0

    if available >= 0
      "#{name} has #{pluralize(available, "#{ghas} license")} available, but #{pluralize(seats_needed, "license")} #{seats_needed > 1 ? "are" : "is"} required to cover #{all_or_additional} committers in this #{kind}. To enable #{ghas}, please ask an administrator to purchase #{pluralize(seats_needed - available, "additional license")}."
    else
      "#{name} is using #{available.abs} more #{ghas} #{available.abs > 1 ? "licenses" : "license"} than they have purchased, and #{pluralize(seats_needed, "license")} #{seats_needed > 1 ? "are" : "is"} required to cover #{all_or_additional} committers in this #{kind}. To enable #{ghas}, please ask an administrator to purchase #{pluralize(seats_needed - available, "additional license")}."
    end
  end

  # Returns a link to a docs page to learn more about billing for advanced security,
  # or returns nil if a suitable docs page is not available for this environment.
  def advanced_security_billing_learn_more_link
    return "#{GitHub.help_url}/github/setting-up-and-managing-billing-and-payments-on-github/about-licensing-for-github-advanced-security" if !GitHub.enterprise?
    nil
  end

  # Returns a link to a docs page to learn more about dependabot alert auto dismissal,
  # or returns nil if a suitable docs page is not available for this environment.
  def dependabot_alerts_auto_dismissal_learn_more_link
    return "#{GitHub.help_url}/code-security/dependabot/dependabot-alerts/using-alert-rules-to-prioritize-dependabot-alerts" if !GitHub.enterprise?
    nil
  end

  # Returns a description of the types of repositories that will be billed for if
  # Advanced Security is enabled. `conditional_prefix` and `conditional_suffix` are
  # added in cases where a limited selection of repositories will be billed
  def advanced_security_billed_repositories_description(owner:, conditional_prefix: "", conditional_suffix: "", includes_public: false)
    return "" if GitHub.enterprise?

    secret_scanning_available = owner.present? && SecretScanning::Features::Owner::TokenScanning.new(owner).feature_available?
    conditional_suffix = "#{conditional_suffix}. The features are free of charge in public repositories" if includes_public && secret_scanning_available
    return "#{conditional_prefix}private and internal#{conditional_suffix}" if !owner.user? && owner.supports_internal_repositories?

    # todo(okaykaylyn): once billing changes for user-namespaced-repos are complete, we have to update the following copy to account for GHEC EMU's/ GHES users
    "#{conditional_prefix}private#{conditional_suffix}"
  end

  memoize def advanced_security_enablement_status
    security_product_enablement_status(
      SecurityProduct::AdvancedSecurity.new(current_repository)
    )
  end

  memoize def advanced_security_blocked_by_policy?
    return false unless advanced_security_enablement_status.error?
    [
      :advanced_security_restricted_by_policy,
      :advanced_security_restricted_by_enablement_policy,
      :advanced_security_restricted_by_secret_scanning_enablement_policy
    ].include? advanced_security_enablement_status.error
  end

  memoize def advanced_security_blocked_by_backfill?
    advanced_security_enablement_status.error == :advanced_security_backfill_in_progress
  end

  memoize def show_advanced_security_blocked_header?
    return false unless advanced_security_blocked_by_policy?
    advanced_security_enablement_status.error != :advanced_security_restricted_by_secret_scanning_enablement_policy
  end

  memoize def dependency_graph_enablement_status
    security_product_enablement_status(
      SecurityProduct::DependencyGraph.new(current_repository)
    )
  end

  def dependency_graph_blocked_by_policy?
    dependency_graph_enablement_status.error == :vulnerability_alerts_restricted_by_enablement_policy
  end

  memoize def dependabot_alerts_enablement_status
    security_product_enablement_status(
      SecurityProduct::VulnerabilityAlerts.new(current_repository)
    )
  end

  def dependabot_alerts_blocked_by_policy?
    dependabot_alerts_enablement_status.error == :vulnerability_alerts_restricted_by_enablement_policy
  end

  memoize def dependabot_updates_enablement_status
    security_product_enablement_status(
      SecurityProduct::VulnerabilityUpdates.new(current_repository)
    )
  end

  def dependabot_updates_blocked_by_policy?
    dependabot_updates_enablement_status.error == :vulnerability_alerts_restricted_by_enablement_policy
  end

  # Defer the current value from Dependabot API as the single point of truth. In the event the service is down
  # or raises, fail over to the Repository config key to avoid blocking the request
  memoize def dependabot_version_updates_config_file_enabled?
    return current_repository.dependabot_config_file_enabled? unless current_repository.fork?
    repository_status = Dependabot::Twirp.update_configs_client.repository_status(repository_id: current_repository.id)

    # If the repository_status is a blank message, Dependabot hasn't setup the Repository yet,
    # so we defer to the Repository setting.
    if repository_status.repository_github_id.zero?
      current_repository.dependabot_config_file_enabled?
    else
      repository_status.using_config_file
    end
  rescue Dependabot::Twirp::ServiceUnavailableError, Dependabot::Twirp::Error
    current_repository.dependabot_config_file_enabled?
  end

  memoize def secret_scanning_enablement_status
    security_product_enablement_status(
      SecurityProduct::TokenScanning.new(current_repository)
    )
  end

  memoize def secret_scanning_blocked_by_policy?
    secret_scanning_enablement_status.error == :token_scanning_restricted_by_enablement_policy
  end

  def render_code_scanning_component?(owner)
    ::SecurityCenter::SecurityFeatures.code_scanning_enabled_for_instance?
  end

  memoize def push_protection_enablement_status
    security_product_enablement_status(
      SecurityProduct::TokenScanningPushProtection.new(current_repository)
    )
  end

  memoize def push_protection_blocked_by_policy?
    push_protection_enablement_status.error == :token_scanning_restricted_by_enablement_policy
  end

  memoize def validity_checks_enablement_status
    security_product_enablement_status(
      SecurityProduct::TokenScanningValidityChecks.new(current_repository)
    )
  end

  memoize def validity_checks_blocked_by_policy?
    validity_checks_enablement_status.error == :token_scanning_restricted_by_enablement_policy
  end

  memoize def lower_confidence_patterns_enablement_status
    security_product_enablement_status(
      SecurityProduct::TokenScanningLowerConfidencePatterns.new(current_repository)
    )
  end

  memoize def lower_confidence_patterns_blocked_by_policy?
    lower_confidence_patterns_enablement_status.error == :token_scanning_restricted_by_enablement_policy
  end

  memoize def generic_secrets_enablement_status
    security_product_enablement_status(
      SecurityProduct::TokenScanningGenericSecrets.new(current_repository)
    )
  end

  memoize def generic_secrets_blocked_by_policy?
    generic_secrets_enablement_status.error == :token_scanning_restricted_by_enablement_policy
  end

  # Is the advanced security Committer Based Billing UI enabled or not
  def advanced_security_configurable?
    return @advanced_security_configurable if defined?(@advanced_security_configurable)
    @advanced_security_configurable = current_repository.advanced_security_configurable?
  end

  protected

  def security_product_enablement_status(product)
    if product.enabled?
      product.can_disable?(actor: current_user, options: {})
    else
      product.can_enable?(actor: current_user, options: {})
    end
  end

  def get_business
    if owner.is_a?(Business)
      owner
    elsif owner.is_a?(Organization)
      owner.business
    end
  end

  def dependabot_security_updates_grouping_prerequisites_prompt
    return if current_repository.vulnerability_updates_grouping_enabled?
    return if current_repository.vulnerability_updates_enabled?

    if !current_repository.vulnerability_alerts_enabled?
      if !current_repository.dependency_graph_enabled?
        "Grouped security updates needs the dependency graph, Dependabot alerts and Dependabot security updates to be enabled, so we'll turn them on too"
      else
        "Grouped security updates needs Dependabot alerts and Dependabot security updates to be enabled, so we'll turn them on too."
      end
    else
      "Grouped security updates needs Dependabot security updates to be enabled, so we'll turn that on too."
    end
  end

  # Returns the `advanced_security_*` partial of `Repositories::Settings::SecurityAnalysisEnablementFormComponent::Data`
  sig { params(blocked_settings: BlockedSettings).returns(T::Hash[Symbol, T.untyped]) }
  def advanced_security_settings_model_partial(blocked_settings:)
    hash = {
      advanced_security_visible: advanced_security_configurable? && !current_repository.archived?,
      advanced_security_enabled: current_repository.advanced_security_enabled?,
      advanced_security_blocked_by_in_progress_setting: blocked_settings.advanced_security?,
      advanced_security_billed_repositories_description:
        if advanced_security_configurable?
          "GitHub Advanced Security features are billed per active committer#{advanced_security_billed_repositories_description(owner: current_repository.owner, conditional_prefix: " in ", conditional_suffix: " repositories")}"
        end,
      advanced_security_billing_learn_more_href: advanced_security_billing_learn_more_link,
      advanced_security_blocked_by_connect_error: SecurityProduct::AdvancedSecurity.blocked_by_connect?,
    }

    # The below properties all depend on Turboghas in some way. Failures here leave the properties above in a good state.
    ghas_would_exceed_seat_allowance = current_repository.enforce_advanced_security_committers_limits? && current_repository.enabling_advanced_security_would_exceed_seat_allowance?

    hash.merge!(
      advanced_security_blocked_by_policy: advanced_security_blocked_by_policy?,
      advanced_security_show_blocked_by_policy_message: show_advanced_security_blocked_header?,
      advanced_security_will_exceed_seat_allowance: ghas_would_exceed_seat_allowance && !current_repository.advanced_security_enabled?,
      advanced_security_blocked_by_seat_count_message:
      if ghas_would_exceed_seat_allowance
        advanced_security_blocked_by_seat_count_message(
          target: current_repository,
          seats_needed: current_repository.seat_usage_increase_if_advanced_security_enabled,
        )
      end,
      advanced_security_license_prompt:
        "#{current_repository.seat_usage_increase_if_advanced_security_enabled}
        #{!owner.advanced_security_license.unlimited_seats? ? " out of #{owner.advanced_security_license.remaining_seats} remaining" : ""}
        GitHub Advanced Security
        #{!owner.advanced_security_license.unlimited_seats? ? "seats" : "seat".pluralize(current_repository.seat_usage_increase_if_advanced_security_enabled)}",
      advanced_security_blocked_by_backfill: advanced_security_blocked_by_backfill?,
      advanced_security_enablement_status: advanced_security_enablement_status,
    )
  rescue AdvancedSecurityLicense::TurboghasError => e
    Failbot.report(e, catalog_service: "github/advanced_security_billing")
    # If we encounter an error here, set enough fallback properties to render a decent state.
    T.must(hash).merge!(
      advanced_security_blocked_by_turboghas_error: true,
      advanced_security_enablement_status: SecurityProduct::Result.new(false, :advanced_security_turboghas_error),
    )
  ensure
    hash
  end

  def show_secret_scanning_ghas_experience?(secret_scanning_ghas_token_scanning)
    secret_scanning_ghas_token_scanning.feature_available? &&
      (current_repository.advanced_security_enabled? || current_repository.public? || current_repository.archived?)
  end

  def button_disabled_no_repos(include_public_repos: false)
    (include_public_repos || GitHub.enterprise?) ? repo_count.zero? : private_repo_count.zero?
  end

  def button_disabled_no_repos_title(title, include_public_repos: false)
    button_disabled_no_repos(include_public_repos: include_public_repos) ? "No applicable repositories" : title
  end

  def security_analysis_update_path(owner)
    if owner.organization?
      T.unsafe(self).settings_org_security_analysis_update_path(owner, owner: owner)
    elsif owner.is_a?(Business)
      T.unsafe(self).settings_security_analysis_update_enterprise_path(owner, owner: owner)
    else
      T.unsafe(self).settings_security_analysis_path
    end
  end

  # variance in the ending of the enable all / disable all popup dialog
  def user_or_org_text(owner, private_only)
    if owner.organization?
      if private_only
        "private repositories in #{owner.name}"
      else
        "repositories in #{owner.name}"
      end
    elsif private_only
      "your private repositories"
    else
      "your repositories"
    end
  end
end
