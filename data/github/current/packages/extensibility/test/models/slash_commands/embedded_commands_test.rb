# typed: true
# frozen_string_literal: true

require "test_helper"

module SlashCommands
  class EmbeddedCommandsTest < GitHub::TestCase
    class TestModel
      include EmbeddedCommands

      attr_accessor :body

      def initialize(body:)
        @body = body
      end
    end

    context "#contains_slash_commands?" do
      test "returns false if no body is set" do
        SlashCommands.expects(:may_contain_commands?).never
        refute TestModel.new(body: "").contains_slash_commands?
      end

      test "performs check if body is provided" do
        SlashCommands.expects(:may_contain_commands?).once.returns(true)
        assert TestModel.new(body: "test").contains_slash_commands?
      end
    end
  end
end
