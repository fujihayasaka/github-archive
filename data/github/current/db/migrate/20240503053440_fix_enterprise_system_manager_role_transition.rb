# typed: true
# frozen_string_literal: true

require "github/transitions/20240503053440_fix_enterprise_system_manager_role"

class FixEnterpriseSystemManagerRoleTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::FixEnterpriseSystemManagerRole.new(arguments)
    transition.run
  end

  def self.down
  end
end
