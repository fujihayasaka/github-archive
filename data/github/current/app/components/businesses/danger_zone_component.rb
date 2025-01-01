# typed: true
# frozen_string_literal: true

class Businesses::DangerZoneComponent < ApplicationComponent
  include TradeControlsHelper
  attr_reader :business

  delegate :cancel_trial_flavor, to: :business

  def initialize(business:)
    @business = business
  end

  private

  def render?
    render_delete_row? ||
    render_rename_row? ||
    render_cancel_trial_row?
  end

  memoize def render_delete_row?
    business.self_serve_deletion_supported?
  end

  memoize def can_delete?
    business.self_serve_deletion_permitted?
  end

  memoize def render_rename_row?
    business.url_change_supported?
  end

  memoize def can_change_url?
    business.self_serve_url_change_permitted?
  end

  memoize def render_cancel_trial_row?
    business.trial? && !business.trial_conversion_initiated?
  end

  memoize def show_trade_restricted_notice?
    business.trade_screening_record.delete_restricted?
  end
end
