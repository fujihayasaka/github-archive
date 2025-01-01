# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class StarterCommandsTest < GitHub::TestCase
    test "starter command is valid" do
      command_data = YAML.load(StarterCommands::STARTER_COMMAND)
      validator = SlashCommands::Validator.new(command_data)
      validator.validate!

      assert validator.valid?
      assert_empty validator.errors.messages, "Expected starter command YAML to be valid, but it wasn't"
      assert_empty validator.deprecation_warnings.messages
    end
  end
end
