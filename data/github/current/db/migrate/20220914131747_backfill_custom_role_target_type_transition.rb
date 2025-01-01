# typed: true
# frozen_string_literal: true

require "github/transitions/20220914131747_backfill_custom_role_target_type"

class BackfillCustomRoleTargetTypeTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::BackfillCustomRoleTargetType.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
