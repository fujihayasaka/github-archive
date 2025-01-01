# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Unprocessable
      class IssuesDisabled < Errors::Execution
        def initialize(*args, **options)
          super(*T.unsafe(["ISSUES_DISABLED", "Issues are disabled", *args]), **options)
        end
      end
    end
  end
end
