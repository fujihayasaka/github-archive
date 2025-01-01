# typed: true
# frozen_string_literal: true

require "github/transitions/20230606200224_add_repo_content_fqps"

class AddRepoContentFqpsTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AddRepoContentFqps.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
