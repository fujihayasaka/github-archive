# typed: true
# frozen_string_literal: true

require "github/transitions/20230208234639_backfill_is_passkey_registration_and_rk_null"

class BackfillIsPasskeyRegistrationAndRkNullTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !GitHub::AppEnvironment.development?
    transition = GitHub::Transitions::BackfillIsPasskeyRegistrationAndRkNull.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
