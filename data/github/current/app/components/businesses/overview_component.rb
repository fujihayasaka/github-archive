# typed: true
# frozen_string_literal: true

class Businesses::OverviewComponent < ApplicationComponent
  attr_reader :business, :user_session

  def initialize(business:, user_session: nil)
    @business = business
    @user_session = user_session
  end

  private

  memoize def first_emu_owner?
    return false unless business.enterprise_managed?
    return false unless current_user

    current_user == business.find_first_emu_owner
  end
end
