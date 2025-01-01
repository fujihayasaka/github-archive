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
    return false unless target.trade_screening_record(ignore_linked_record: true).persisted?

    target.has_valid_payment_method?(feature_type: :noncommercial)
  end

  sig { returns(T::Array[ActiveRecord::Relation]) }
  memoize def linked_orgs_to_warn_about
    return [] unless target.user?

    target.orgs_linked_to_screening_record
  end

  private

  sig { returns(T.any(::User, ::Organization)) }
  attr_reader :target
end
