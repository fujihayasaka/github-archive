# typed: true
# frozen_string_literal: true

require "github/transitions/20231124131604_move_ipr_ignore_whitespace_key_values"

class MoveIprIgnoreWhitespaceKeyValuesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::MoveIprIgnoreWhitespaceKeyValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
