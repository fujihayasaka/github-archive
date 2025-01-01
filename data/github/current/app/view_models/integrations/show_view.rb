# typed: true
# frozen_string_literal: true

class Integrations::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  BETA_FEATURE_FLAGS = {
    user_token_expiration: "user_token_expiration_opt_in",
    apps_multiple_callback_urls: "apps_multiple_callback_urls_opt_in",
  }

  BETA_FEATURE_MODEL_ATTRIBUTES = {
    "user_token_expiration_opt_in" => :user_token_expiration
  }

  BETA_FEATURE_NAMES = {
    "user_token_expiration_opt_in" => "User-to-server token expiration",
    "apps_multiple_callback_urls_opt_in" => "Multiple User authorization callback URLs",
  }

  LAUNCHED_FEATURES = %i[
    user_token_expiration
  ]

  def self.toggle_feature(flag, value, integration:)
    return unless %w[enable disable].include?(value)
    return unless BETA_FEATURE_FLAGS.values.include?(flag)

    global_key = BETA_FEATURE_FLAGS.key(flag)
    return unless GitHub.flipper[global_key].enabled?(integration.owner)

    case value
    when "disable"
      GitHub.flipper[flag.to_sym].disable(integration)
    when "enable"
      GitHub.flipper[flag.to_sym].enable(integration)
    end
  end

  def self.toggle_feature_flash_message(flag, value, integration:)
    feature_name = BETA_FEATURE_NAMES[flag]
    past_tense_value = case value
    when "disable"
      "disabled"
    when "enable"
      "enabled"
    end

    "#{feature_name} is being #{past_tense_value} for #{integration.name}."
  end

  def self.model_owned_opt_in_attribute(flag)
    BETA_FEATURE_MODEL_ATTRIBUTES[flag]
  end

  def self.enable_or_disable_to_boolean(value)
    case value
    when "disable"
      false
    when "enable"
      true
    end
  end

  attr_reader :integration, :page

  delegate :pending_transfer?, :public?, :can_make_private?, :description,
           :transfer, :hook, :can_delete?, to: :integration

  delegate :pricing_url?, :pricing_url, :documentation_url?, :documentation_url,
           :tos_url?, :tos_url, :support_url?, :support_url,
           :status_url?, :status_url, :privacy_policy_url, to: :listing

  def show_features?
    features.any?
  end

  # Public: Determine if "Install app" link should be shown. Full-trust GitHub
  # App installations should never be manually installed by end-users, so
  # "Install app" should never be visible for those apps. Otherwise, checks to
  # make sure the integration is installable anywhere by the current user.
  #
  # Returns a Boolean.
  def hide_install_app_section?
    return true unless Apps::Internal.capable?(:user_installable, app: integration)
    return true unless integration.installable_by?(current_user)
    false
  end

  # Public: Determine if a field for setting the given GitHub App's bgcolor should be shown in the
  # page.
  #
  # Returns a Boolean.
  def allow_editing_bgcolor?
    if GitHub.enterprise?
      integration.primary_avatar.present?
    else
      return false unless integration.primary_avatar

      listing = integration.marketplace_listing
      listing.nil? || !listing.publicly_listed?
    end
  end

  def features
    return [] unless listing && listing.features.any?

    listing.features
  end

  def beta_features?
    return true if defined?(LAUNCHED_FEATURES) && LAUNCHED_FEATURES.any?
    BETA_FEATURE_FLAGS.any? do |(global_flag, _opt_in)|
      GitHub.flipper[global_flag].enabled?(integration.owner)
    end
  end

  def beta_feature_available?(flag)
    global_key = BETA_FEATURE_FLAGS.key(flag)
    return true if LAUNCHED_FEATURES.include?(global_key)

    GitHub.flipper[global_key].enabled?(integration.owner)
  end

  def beta_feature_enabled?(flag)
    if (attribute = self.class.model_owned_opt_in_attribute(flag))
      integration[attribute]
    else
      GitHub.flipper[flag].enabled?(integration)
    end
  end

  def beta_feature_toggle_value(flag)
    beta_feature_enabled?(flag) ? "disable" : "enable"
  end

  def enterprise_owned?
    integration.enterprise_owned?
  end

  def beta_feature_toggle_submit_value(flag)
    beta_feature_enabled?(flag) ? "Opt-out" : "Opt-in"
  end

  def show_more_info?
    listing.present?
  end

  def selected_link
    :integrations
  end

  def hook_url
    hook&.url
  end

  def make_private_tooltip_content
    reason = if integration.owner.is_enterprise_managed?
      "Enterprise Managed Accounts cannot have private integrations."
    else
      "it is " + (listing.present? ? "part of the Integrations Directory." : "already installed on other accounts.")
    end

    "This integration cannot be made private since #{reason}"
  end

  def delete_tooltip_content
    "This integration cannot be deleted since it has active marketplace subscriptions."
  end

  def transfer_tooltip_content
    return if integration.can_transfer_ownership?

    "This GitHub app cannot be transferred because it is private and has remaining installations."
  end

  def events
    integration.default_events.map do |event_type|
      Hook::EventRegistry.for_event_type(event_type)
    end.sort_by(&:display_name)
  end

  def transfer_target
    transfer.target
  end

  def keys_classes
    klasses = []
    klasses << "has-keys" if integration.public_keys.any?
    klasses << "multi-keys" if integration.public_keys.count > 1
    klasses.join(" ")
  end

  def show_app_id_deprecation_message?
    integration.owner.feature_enabled?(:jwt_client_id_discourage_app_id)
  end

  def eligible_for_marketplace?
    return false unless GitHub.marketplace_enabled?
    return false unless public?
    return false if is_enterprise_managed?
    true
  end

  private

  def listing
    @listing ||= integration.integration_listing
  end

  def is_enterprise_managed?
    owner = integration.owner
    case owner
    when Organization
      owner.enterprise_managed_user_enabled?
    when User
      owner.is_enterprise_managed?
    else
      false
    end
  end
end
