# typed: true
# frozen_string_literal: true

require "github/transitions/20221026145312_two_factor_credential_normalization"

class TwoFactorCredentialNormalizationTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::TwoFactorCredentialNormalization.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
