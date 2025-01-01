# typed: true
# frozen_string_literal: true

require "github/transitions/20230921184946_add_custom_properties_organization_fgps"

class AddCustomPropertiesOrganizationFgpsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddCustomPropertiesOrganizationFgps.new(dry_run: false)
    transition.run
  end

  def self.down
  end
end
