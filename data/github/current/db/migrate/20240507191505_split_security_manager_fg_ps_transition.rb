# typed: true
# frozen_string_literal: true

require "github/transitions/20240507191505_split_security_manager_fg_ps"

class SplitSecurityManagerFgPsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::SplitSecurityManagerFgPs.new(arguments)
    transition.run
  end

  def self.down
  end
end
