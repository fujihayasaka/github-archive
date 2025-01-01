# typed: strict
# frozen_string_literal: true

module PullRequests
  module CommentPosition
    module Repositioner
      # Mock class responsible for stubing and simulating responses from side effects and IO to enable testing
      # without the need for git or a database.
      class MockCommand
        include Repositioner::ICommand
      end
    end
  end
end
