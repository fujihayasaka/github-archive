# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    class Unprocessable
      class UserProjectsDisabled < Errors::Execution
        # Related https://github.com/github/memex/issues/17670
        def initialize(*args, **options)
          super(*T.unsafe(["USER_PROJECTS_DISABLED", "User Projects are not enabled for this enterprise", *args]), **options)
        end
      end
    end
  end
end
