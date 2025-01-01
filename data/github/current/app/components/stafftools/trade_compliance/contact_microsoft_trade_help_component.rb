# typed: strict
# frozen_string_literal: true

class Stafftools::TradeCompliance::ContactMicrosoftTradeHelpComponent < ApplicationComponent
  extend T::Sig
  include StafftoolsHelper
  include Stafftools::AccessControlHelper

  sig { params(target: Billing::Types::Account, staffer: User).void }
  def initialize(target:, staffer:)
    @target = target
    @staffer = staffer
  end

  sig { returns(T::Boolean) }
  def authorized_staffer?
    controller = Stafftools::TradeCompliance::MicrosoftTradeHelpEmailsController

    stafftools_action_authorized?(controller: controller, action: :create)
  end

  private

  sig { returns(Billing::Types::Account) }
  attr_reader :target
  sig { returns(User) }
  attr_reader :staffer
end
