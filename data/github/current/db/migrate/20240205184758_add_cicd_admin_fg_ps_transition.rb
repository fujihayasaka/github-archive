# typed: true
# frozen_string_literal: true

require "github/transitions/20240205184758_add_cicd_admin_fg_ps"

class AddCicdAdminFgPsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddCicdAdminFgPs.new(arguments)
    transition.perform
  end

  def self.down
  end
end
