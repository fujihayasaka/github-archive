# typed: true
# frozen_string_literal: true

require "github/transitions/20221114143945_multiple_user_two_factor_credential_repair"

class MultipleUserTwoFactorCredentialRepairTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::MultipleUserTwoFactorCredentialRepair.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
