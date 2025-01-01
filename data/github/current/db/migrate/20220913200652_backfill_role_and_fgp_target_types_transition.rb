# typed: true
# frozen_string_literal: true

require "github/transitions/20220913200652_backfill_role_and_fgp_target_types"

class BackfillRoleAndFgpTargetTypesTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillRoleAndFgpTargetTypes.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
