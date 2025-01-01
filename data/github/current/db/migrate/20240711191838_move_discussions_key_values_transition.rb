# typed: true
# frozen_string_literal: true

require "github/transitions/20240711191838_move_discussions_key_values"

class MoveDiscussionsKeyValuesTransition < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveDiscussionsKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
