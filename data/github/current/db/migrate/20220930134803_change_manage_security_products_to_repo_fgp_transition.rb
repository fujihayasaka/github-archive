# typed: true
# frozen_string_literal: true

require "github/transitions/20220930134803_change_manage_security_products_to_repo_fgp"

class ChangeManageSecurityProductsToRepoFgpTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::ChangeManageSecurityProductsToRepoFgp.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
