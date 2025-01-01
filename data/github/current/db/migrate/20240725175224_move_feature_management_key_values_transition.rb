# typed: true
# frozen_string_literal: true

require "github/transitions/20240725175224_move_feature_management_key_values"

class MoveFeatureManagementKeyValuesTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Collab)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveFeatureManagementKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
