# typed: true
# frozen_string_literal: true

require "github/transitions/20220607014142_add_branch_protection_fgps"

class AddBranchProtectionFgpsTransition < ActiveRecord::Migration[7.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddBranchProtectionFgps.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
