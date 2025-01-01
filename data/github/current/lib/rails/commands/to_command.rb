# typed: true
# frozen_string_literal: true
require_relative "./test_oracle_command"

class Rails::Command::ToCommand < Rails::Command::TestOracleCommand
  # Alias test_oracle command to to
  def self.all_commands
    super.tap do |commands|
      commands["to"] = commands["test_oracle"]
    end
  end
end
