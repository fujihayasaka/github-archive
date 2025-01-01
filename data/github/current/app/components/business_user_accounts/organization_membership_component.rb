# typed: true
# frozen_string_literal: true

class BusinessUserAccounts::OrganizationMembershipComponent < ApplicationComponent
  attr_reader :user, :organization, :business

  def initialize(user:, organization:, business: nil)
    @user = user
    @organization = organization
    @business = business
  end
end
