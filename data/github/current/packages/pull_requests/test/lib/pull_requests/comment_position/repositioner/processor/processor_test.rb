# typed: strict
# frozen_string_literal: true

require "test_helper"
require_relative "mock_command"
require_relative "test_case"

module PullRequests
  module CommentPosition
    module Repositioner
      class ProcessorTest < TestCase
        test "no actions are performed when the requests collection is empty" do
          command = Logging::Commands.new(delegate: MockCommand.new)
          processor = Processor.new(command:, requests: [], range: build_diff_range)
          processor.call

          assert_equal [], command.actions
        end
      end
    end
  end
end
