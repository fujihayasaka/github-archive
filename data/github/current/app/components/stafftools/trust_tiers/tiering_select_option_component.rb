# typed: true
# frozen_string_literal: true
class Stafftools::TrustTiers::TieringSelectOptionComponent < ApplicationComponent
  attr_reader :tier, :tier_name, :user

  def initialize(user, tier, tier_name)
    @user = user
    @tier = tier
    @tier_name = tier_name
  end
end
