# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::FreeSubscriptionComponent < ApplicationComponent
  sig { returns(Copilot::User) }
  attr_reader :copilot_user

  sig { returns(T.nilable(Copilot::EngagedOssUser)) }
  attr_reader :engaged_oss_user

  sig { returns(T.nilable(Copilot::FreeUser)) }
  attr_reader :free_user

  sig { returns(T.nilable(::Coupon)) }
  attr_reader :coupon

  sig { returns(T::Boolean) }
  attr_reader :has_free_access

  sig { returns(T.nilable(String)) }
  attr_reader :coupon_type

  sig { returns(T::Boolean) }
  attr_reader :github_star

  sig { returns(T::Boolean) }
  attr_reader :any_orgs_using_cfb

  sig { returns(T.nilable(::Billing::Public::SubscriptionItem)) }
  attr_reader :subscription_item

  sig do
    params(
      copilot_user: Copilot::User,
      engaged_oss_user: T.nilable(Copilot::EngagedOssUser),
      free_user: T.nilable(Copilot::FreeUser),
      coupon: T.nilable(::Coupon),
      github_star: T::Boolean,
      any_orgs_using_cfb: T::Boolean,
      subscription_item: T.nilable(::Billing::Public::SubscriptionItem),
    ).void
  end
  def initialize(copilot_user, engaged_oss_user: nil, free_user: nil, coupon: nil, github_star: false, any_orgs_using_cfb: false, subscription_item: nil)
    @copilot_user              = copilot_user
    @engaged_oss_user          = engaged_oss_user
    @free_user                 = free_user
    @coupon                    = coupon
    @subscription_item         = T.let(subscription_item, T.nilable(::Billing::Public::SubscriptionItem))

    has_free_access            = ((free_user.present? && free_user.next_check_at > Date.current && free_user.subscribed?) || has_active_edu_subscription?) || false

    @has_free_access           = T.let(has_free_access, T::Boolean)
    @github_star               = github_star
    @coupon_type               = T.let(load_coupon_type, T.nilable(String))
    @any_orgs_using_cfb        = any_orgs_using_cfb
  end

  sig { returns(T::Boolean) }
  def render?
    true
  end

  sig { returns(T::Boolean) }
  def would_have_free_access?
    return false if @copilot_user.free_user_blocked?
    @github_star || @engaged_oss_user.present? || @coupon_type.present?
  end

  sig { returns(T.nilable(String)) }
  def would_have_free_access_reason
    return "Coupon Blocked" if @copilot_user.free_user_blocked?

    return "No Free Access" unless would_have_free_access?

    return "GitHub Star" if @github_star
    return "#{@coupon_type} Coupon" if @coupon_type.present?

    "Engaged OSS"
  end

  sig { returns(String) }
  def subscription_item_status
    item = subscription_item

    if item.nil?
      "None"
    elsif item.active?
      "#{item.product_identifier.product_key} (Active)"
    else
      "#{item.product_identifier.product_key} (Inactive)"
    end
  end

  sig { returns(T.any(TrueClass, String)) }
  def complimentary_access_status
    if has_free_access
      true
    else
      current_free_user = free_user
      if current_free_user
        current_free_user.subscribed? ? "No" : "Not Claimed"
      elsif coupon_type == "Student" && !has_active_edu_subscription?
        "Not Claimed"
      else
        "No"
      end
    end
  end

  sig { returns(Symbol) }
  def complimentary_access_label_scheme
    case complimentary_access_status
    when "No"
      :danger
    when "Not Claimed"
      :warning
    else
      :success
    end
  end

  sig { returns(T::Boolean) }
  def has_active_edu_subscription?
    copilot_user.edu_signup_enabled? && copilot_user.active_subscription_is_edu
  end

  sig { returns(T::Boolean) }
  def any_edu_subscription_items?
    copilot_user.all_copilot_subscription_items.any? do |item|
      product_identifier = ::Billing::Public::SubscriptionItem.new(item).product_identifier
      copilot_user.copilot_edu_product_identifier.same?(product_identifier, match_billing_cycle: false)
    end
  end

  sig { returns(Symbol) }
  def subscription_item_label_scheme
    item = subscription_item

    if item.nil?
      :secondary
    elsif item.active?
      :success
    else
      :danger
    end
  end

  sig { returns(T.nilable(Date)) }
  memoize def coupon_expiration_date
    return nil unless @coupon.present?
    coupon_redemption = Copilot::FreeUser.educational_coupon_redemption(copilot_user)
    coupon_redemption&.expires_at&.to_date
  end

  sig { returns(T.nilable(String)) }
  def load_coupon_type
    return nil unless @coupon.present?
    return "MS MVP" if @coupon.code.start_with?("MVP-")
    return "Student" if @coupon.code.start_with?("student")
    return "Faculty" if @coupon.code.start_with?("faculty")
    nil
  end

  sig { returns(T::Boolean) }
  def show_create_campus_expert_button?
    current_free_user = free_user
    if current_free_user.present?
      return false if current_free_user.type == Copilot::FreeUser::CAMPUS_EXPERT
    end

    coupon_redemption = Copilot::FreeUser.educational_coupon_redemption(copilot_user)
    return false unless coupon_redemption.present?

    copilot_user.user_object.current_campus_expert?
  end

  DISPLAY_NAMES = T.let({
    "Campus Expert" => "Influencer [Pro]",
    "Complimentary Access" => "Influencer [Pro+]",
    "Educational" => "Student",
    "EngagedOSS" => "Engaged OSS [Pro]",
    "Faculty" => "Faculty [Pro]",
    "GitHub Star" => "GitHub Star [Pro+]",
    "Hey GitHub" => "Hey GitHub [Pro]",
    "MS MVP" => "MS MVP [Pro+]",
    "Workshop" => "Workshop [Pro+]",
    "Y Combinator" => "Y Combinator [Pro]",
  }.freeze, T::Hash[String, String])

  sig { params(type: String).returns(String) }
  def display_name_for_type(type)
    if type == "Campus Expert" && copilot_user.user_object.current_campus_expert?
      return "Campus Expert [Pro]"
    end

    DISPLAY_NAMES.fetch(type, type)
  end

  sig { returns(String) }
  def effective_free_user_type
    current_free_user = free_user
    if current_free_user.present?
      current_free_user.free_user_type
    else
      Copilot::FreeUser::EDUCATIONAL.name
    end
  end

  sig { returns(T::Boolean) }
  def show_complimentary_access_type_dropdown?
    free_user.present? || has_active_edu_subscription? || any_edu_subscription_items?
  end

  sig { returns(T::Boolean) }
  def show_subscribe_to_edu_sku_button?
    # Only show if user has a valid student coupon
    return false unless copilot_user.has_valid_student_coupon?

    # Only show if user has no active Copilot subscription item at all
    return false if copilot_user.copilot_active_subscription_item.present?

    # Only show if user doesn't already have an active EDU subscription
    !has_active_edu_subscription?
  end
end
