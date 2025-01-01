# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::MicrosoftTradeHelpEmailComponent < ApplicationComponent
  include Stafftools::TradeComplianceHelper

  sig { returns(::User) }
  attr_reader :staffer

  sig { returns(T.nilable(Billing::Types::Account)) }
  attr_reader :target

  sig { params(staffer: ::User, target: T.nilable(Billing::Types::Account)).void }
  def initialize(staffer:, target: nil)
    @staffer = staffer
    @target = target
  end

  sig { returns(T::Boolean) }
  def target?
    target.present?
  end

  sig { returns(String) }
  def cc_email
    staffer.email
  end

  sig { returns(String) }
  def subject_line
    return "" unless target?
    "Request for additional information for account screening status"
  end

  sig { returns(String) }
  def email_content
    return "" unless target?
    microsoft_trade_help_default_template(T.must(target))
  end

  private

  sig { returns(T.nilable(::AccountScreeningProfile)) }
  def profile
    return nil unless target?
    T.must(target).trade_screening_record
  end

  sig { returns(T.nilable(String)) }
  def external_uuid
    profile&.external_uuid
  end

  sig { returns(T.nilable(String)) }
  def screening_status
    profile&.msft_trade_screening_status
  end
end
