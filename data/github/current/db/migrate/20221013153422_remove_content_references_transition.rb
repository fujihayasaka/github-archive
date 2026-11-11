# typed: true
# frozen_string_literal: true

require "github/transitions/20221013153422_remove_content_references"

class RemoveContentReferencesTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::RemoveContentReferences.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
