# typed: strict
# frozen_string_literal: true

class Stafftools::Copilot::FreeSubscriptionComponent < ApplicationComponent
  extend T::Sig

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

  sig do
    params(
      copilot_user: Copilot::User,
      engaged_oss_user: T.nilable(Copilot::EngagedOssUser),
      free_user: T.nilable(Copilot::FreeUser),
      coupon: T.nilable(::Coupon),
      github_star: T::Boolean,
      any_orgs_using_cfb: T::Boolean,
    ).void
  end
  def initialize(copilot_user, engaged_oss_user: nil, free_user: nil, coupon: nil, github_star: false, any_orgs_using_cfb: false)
    @copilot_user              = copilot_user
    @engaged_oss_user          = engaged_oss_user
    @free_user                 = free_user
    @coupon                    = coupon

    has_free_access            = (free_user.present? && free_user.next_check_at > Date.current && free_user.subscribed?) || false

    @has_free_access           = T.let(has_free_access, T::Boolean)
    @github_star               = github_star
    @coupon_type               = T.let(load_coupon_type, T.untyped)
    @github_star               = github_star
    @any_orgs_using_cfb        = any_orgs_using_cfb
  end

  sig { returns(T::Boolean) }
  def render?
    !@any_orgs_using_cfb
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
    return "Educational" if @coupon.code.start_with?("student")
    return "Faculty" if @coupon.code.start_with?("faculty")
    nil
  end
end
