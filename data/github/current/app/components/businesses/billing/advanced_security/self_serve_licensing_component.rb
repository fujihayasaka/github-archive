# typed: true
# frozen_string_literal: true
class Businesses::Billing::AdvancedSecurity::SelfServeLicensingComponent < ApplicationComponent
  extend T::Sig

  sig { returns Business }
  attr_reader :business

  sig { returns User }
  attr_reader :user

  sig { params(business: Business, user: User).void }
  def initialize(business:, user:)
    @business = business
    @user = user
  end
end
