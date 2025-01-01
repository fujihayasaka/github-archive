# typed: true
# frozen_string_literal: true

require "github/transitions/20250512193754_add_secrets_variables_write_to_repo_role"

# rubocop:disable GitHub/ConnectionClassPresentInMigration
# requiring a connection class is not necessary for transition migrations
class AddSecretsVariablesWriteToRepoRoleTransition < ActiveRecord::Migration[8.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?

    arguments = GitHub::Transitions::Arguments.new(dry_run: false)
    transition = GitHub::Transitions::AddSecretsVariablesWriteToRepoRole.new(arguments)
    transition.run
  end

  def self.down
  end
end
# rubocop:enable GitHub/ConnectionClassPresentInMigration
