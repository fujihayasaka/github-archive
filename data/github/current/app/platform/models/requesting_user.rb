# typed: true
# frozen_string_literal: true

class Platform::Models::RequestingUser
  include GitHub::Relay::GlobalIdentification

  attr_reader :user

  delegate :async_plan, :teams, to: :user

  def initialize(user)
    @user = user
  end
end
