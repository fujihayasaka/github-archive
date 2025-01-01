# typed: true
# frozen_string_literal: true
require_relative "./test_changes_command"

class Rails::Command::TcCommand < Rails::Command::TestChangesCommand
  # Alias test_changes command to tc
  def self.all_commands
    super.tap do |commands|
      commands["tc"] = commands["test_changes"]
    end
  end
end
