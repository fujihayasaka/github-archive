# typed: true
# frozen_string_literal: true

require "github/transitions/20240227194506_decrypt_ghes_columns"

class DecryptGhesColumnsTransition < ActiveRecord::Migration[7.2]
  def self.up
    return if !GitHub.enterprise?
    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::DecryptGhesColumns.new(arguments)
    transition.run
  end

  def self.down
  end
end
