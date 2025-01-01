# typed: true
# frozen_string_literal: true

require "github/transitions/20220921114258_add_edit_repo_protections_fgp"

class AddEditRepoProtectionsFgpTransition < ActiveRecord::Migration[7.0]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddEditRepoProtectionsFgp.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
