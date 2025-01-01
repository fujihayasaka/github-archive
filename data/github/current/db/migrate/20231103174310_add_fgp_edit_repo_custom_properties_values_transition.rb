# typed: true
# frozen_string_literal: true

require "github/transitions/20231103174310_add_fgp_edit_repo_custom_properties_values"

class AddFgpEditRepoCustomPropertiesValuesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddFgpEditRepoCustomPropertiesValues.new(dry_run: false)
    transition.run
  end

  def self.down
  end
end
