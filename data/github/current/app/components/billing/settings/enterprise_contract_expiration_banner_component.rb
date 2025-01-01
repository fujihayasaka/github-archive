# typed: strict
# frozen_string_literal: true

class Billing::Settings::EnterpriseContractExpirationBannerComponent < ApplicationComponent

  extend T::Sig

  sig { returns(Business) }
  attr_reader :business

  sig { returns(User) }
  attr_reader :current_user

  sig { params(business: Business, current_user: User).void }
  def initialize(business:, current_user:)
    @business = T.let(business, Business)
    @current_user = T.let(current_user, User)
  end

  sig { returns(String) }
  def banner_color
    case expiration_status
    when :severe
      "color-bg-severe color-border-severe"
    when :attention
      "color-bg-attention color-border-attention"
    else
      ""
    end
  end

  sig { returns(String) }
  def text_color
    case expiration_status
    when :severe
      "color-bg-severe"
    when :attention
      "color-bg-attention"
    else
      ""
    end
  end

  sig { returns(T::Boolean) }
  memoize def business_adminable_by_user?
    business.adminable_by?(current_user)
  end

  sig { returns(String) }
  def notice_name
    "sales_serve_enterprise_contract_expiration"
  end

  sig { returns(T::Boolean) }
  def render?
    return false unless business.feature_enabled?(:ghe_sales_serve_renewals)
    return false unless business.invoiced?
    return false unless show_banner?
    return false unless days_to_expiration < 90

    !Growth::NoticeDismissal.new(current_user).dismissed_business_notice?(notice_name, business_id: T.must(business.id), per_user: notice_per_user?)
  end

  sig { returns(T::Boolean) }
  memoize def is_billing_manager?
    business.billing_manager?(current_user)
  end

  sig { returns(T::Boolean) }
  def show_banner?
    business_adminable_by_user? || is_billing_manager?
  end

  sig { returns(String) }
  def billing_end_date
    business.billing_term_ends_on.strftime("%B %d, %Y")
  end

  sig { returns(Integer) }
  def days_to_expiration
    (business.billing_term_ends_on - GitHub::Billing.now.to_date).to_i
  end

  private

  sig { returns(T.nilable(Symbol)) }
  def expiration_status
    if days_to_expiration < 15
      :severe
    elsif days_to_expiration < 90
      :attention
    end
  end

  sig { returns(T::Boolean) }
  def notice_per_user?
    true
  end
end
