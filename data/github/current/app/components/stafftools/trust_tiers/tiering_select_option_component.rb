# typed: true
# frozen_string_literal: true

class Stafftools::TrustTiers::TieringSelectOptionComponent < ApplicationComponent
  attr_reader :tier, :tier_name, :change_tier_path

  def initialize(change_tier_path, tier, tier_name)
    @change_tier_path = change_tier_path
    @tier = tier
    @tier_name = tier_name
  end
end
