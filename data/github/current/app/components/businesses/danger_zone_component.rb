# typed: strict
# frozen_string_literal: true

class Businesses::DangerZoneComponent < ApplicationComponent
  include TradeControlsHelper
  sig { returns(Business) }
  attr_reader :business

  delegate :cancel_trial_flavor, to: :business

  sig { params(business: Business).void }
  def initialize(business:)
    @business = business
  end

  private

  sig { returns(T::Boolean) }
  def render?
    render_delete_row? ||
    render_rename_row? ||
    render_cancel_trial_row?
  end

  sig { returns(T::Boolean) }
  memoize def render_delete_row?
    business.self_serve_deletion_supported?
  end

  sig { returns(T::Boolean) }
  memoize def can_delete?
    business.self_serve_deletion_permitted?
  end

  sig { returns(T::Boolean) }
  memoize def render_rename_row?
    business.url_change_supported?
  end

  sig { returns(T::Boolean) }
  memoize def can_change_url?
    business.self_serve_url_change_permitted?
  end

  sig { returns(T::Boolean) }
  memoize def render_cancel_trial_row?
    business.trial? && !business.trial_conversion_initiated?
  end

  sig { returns(T::Boolean) }
  memoize def show_trade_restricted_notice?
    business.trade_compliance_delete_restriction?
  end
end
