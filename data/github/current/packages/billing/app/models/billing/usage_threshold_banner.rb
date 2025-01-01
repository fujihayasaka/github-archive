# typed: true
# frozen_string_literal: true

# Class with methods to fetch state when initializing a Billing::UsageThresholdBannerComponent
class Billing::UsageThresholdBanner
  include UrlHelpers

  # Initialize the UsageThresholdBanner
  #
  # owner        - The Business, Organization, or User that is being viewed on the billing settings page.
  # actor        - The user viewing the billing settings page.
  # budget_group - The budget group that the banner will be used for (See Billing::Budget for a list of all possible budget groups)
  def initialize(owner:, actor:, budget_group:)
    @owner = owner
    @actor = actor
    @budget_group = budget_group
  end

  # Title text to be displayed in the banner
  #
  # Returns String
  def title_text
    active_usage_notification&.text
  end

  # Text to be displayed in banner describing next steps
  #
  # Returns String
  def body_text
    active_usage_notification&.action_text
  end

  # Is the feature flag enabled to have banners be dismissable?
  #
  # Returns Boolean
  def dismiss_enabled?
    FeatureFlag.vexi.enabled_or_raise?(:never_stop_threshold_banner_dismissable, billable_owner) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  # Has the actor already dismissed this banner?
  #
  # Returns Boolean
  def has_dismissed?
    !active_usage_notification.present?
  end

  # The path to dismiss this banner for the given owner and threshold.
  #
  # Returns String
  def dismissal_path
    return unless threshold_spending_limit_notice_key

    billing_notifications_dismissals_path \
      account_id: billable_owner.id,
      account_type: billable_owner.class.name,
      notice_key: threshold_spending_limit_notice_key,
      product_tags: threshold_product_tags
  end

  # Should we show the update spending limit link?
  #
  # Returns Boolean
  def show_update_spending_limit?
    !owner.is_organization_billed_through_business?
  end

  # Which variant flash message to show?
  #
  # Returns Symbol
  def variant
    if within_entitlements? && overages_allowed?
      :default
    elsif threshold_text == "info" || threshold_text == "warn"
      :warning
    elsif threshold_text == "error"
      :danger
    else
      :none
    end
  end

  def active_usage_notification
    @active_usage_notification ||= non_dismissed_usage_notifications.first
  end

  private

  attr_reader :owner, :actor, :budget_group

  def usage_notifications
    # Defaults to shared budget group and products
    @usage_notifications ||=
      Billing::Notifications::UsageNotification.new(owner, budget_group: budget_group).active_notifications
  end

  def non_dismissed_usage_notifications
    @non_dismissed_usage_notifications ||= usage_notifications.reject do |usage_notification|
      notification_dismissed?(usage_notification)
    end
  end

  def notification_dismissed?(notification)
    notification.product_tags.all? do |tag|
      notice_dismissal.exists?(notification_key_for(notification), product_tag: tag)
    end
  end

  def notice_dismissal
    @notice_dismissal ||= Billing::Notifications::Dismissal.new \
      account: billable_owner,
      actor_id: actor.id
  end

  def threshold_text
    active_usage_notification&.threshold_text
  end

  def within_entitlements?
    active_usage_notification&.within_entitlements
  end

  def threshold_product_tags
    active_usage_notification&.product_tags
  end

  def overages_allowed?
    billable_owner.metered_billing_overage_allowed?
  end

  def threshold_spending_limit_notice_key
    return unless threshold_text
    notification_key_for(active_usage_notification)
  end

  def notification_key_for(notification)
    if notification.within_entitlements
      "threshold_entitlements_#{notification.threshold_text}"
    else
      "threshold_spending_limit_#{notification.threshold_text}"
    end
  end

  def billable_owner_is_business?
    billable_owner.instance_of?(Business)
  end

  def billable_owner
    @billable_owner ||= owner.billable_owner
  end
end
