# typed: true
# frozen_string_literal: true

require "github/transitions/20220609193838_set_key_link_is_alphanumeric_to_false"

class SetKeyLinkIsAlphanumericToFalseTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::SetKeyLinkIsAlphanumericToFalse.new(dry_run: false)
    transition.perform
  end
end
