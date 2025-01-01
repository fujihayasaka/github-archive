# typed: true
# frozen_string_literal: true

require "github/transitions/20240311133747_delete_invalid_memex_date_values"

class DeleteInvalidMemexDateValuesTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::DeleteInvalidMemexDateValues.new(arguments)
    transition.run
  end

  def self.down
  end
end
