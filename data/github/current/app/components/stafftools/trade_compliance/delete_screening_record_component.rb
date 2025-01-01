# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::DeleteScreeningRecordComponent < ApplicationComponent
  sig { params(target: T.any(::User, ::Organization)).void }
  def initialize(target:)
    @target = target
  end

  sig { returns(T::Boolean) }
  def render?
    target.user? || target.organization?
  end

  sig { returns(T::Boolean) }
  def warn_about_payment_method_removal?
    return false unless direct_trade_screening_record.persisted?

    target.has_valid_payment_method?(feature_type: :noncommercial)
  end

  sig { returns(T::Array[Organization]) }
  memoize def linked_orgs_to_warn_about
    return [] unless target.user?

    target.orgs_linked_to_billing_contact
  end

  sig { returns(T::Boolean) }
  def delete_restricted?
    return false unless direct_trade_screening_record.persisted?
    direct_trade_screening_record.delete_restricted?
  end

  # Accounts trade screening record, ignoring linking, for displaying trade screening information in stafftools
  sig { returns(AccountScreeningProfile) }
  def direct_trade_screening_record
    target.trade_screening_record(ignore_linked_record: true)
  end

  private

  sig { returns(T.any(::User, ::Organization)) }
  attr_reader :target
end
