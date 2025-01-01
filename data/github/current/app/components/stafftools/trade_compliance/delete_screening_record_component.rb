# typed: true
# frozen_string_literal: true

class Stafftools::TradeCompliance::DeleteScreeningRecordComponent < ApplicationComponent
  # user - a User or organization
  def initialize(user:)
    @user = user
  end

  def render?
    user.user? || user.organization?
  end

  def warn_about_payment_method_removal?
    return false unless user.trade_screening_record(ignore_linked_record: true).persisted?

    user.has_valid_payment_method?(feature_type: :noncommercial)
  end

  memoize def linked_orgs_to_warn_about
    return [] unless user.user?

    user.orgs_linked_to_screening_record
  end

  private

  attr_reader :user
end
