# typed: true
# frozen_string_literal: true

class Stafftools::TradeCompliance::SdnUnsuspendIndividualComponent < ApplicationComponent
  # user - a User not organization
  def initialize(user:)
    @user = user
  end

  def render?
    user.user? && user.sdn_suspended?
  end

  private

  attr_reader :user
end
