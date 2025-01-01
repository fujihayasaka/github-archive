# typed: true
# frozen_string_literal: true

require "github/transitions/20240424151841_add_enterprise_security_manager"

class AddEnterpriseSecurityManagerTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddEnterpriseSecurityManager.new(arguments)
    transition.run
  end

  def self.down
  end
end
