# typed: true
# frozen_string_literal: true

# TODO: This error should be removed, as projects is enabled everywhere now (GHEC, GHES, etc.).
module Platform
  module Errors
    class Unprocessable
      class ProjectsNewDisabled < Errors::Execution
        # Per https://github.com/github/planning-tracking/issues/1134
        # Projects V2/Projects New/Memex will be dark shipped for GHES 3.7 and
        # so only enterprises that have not enabled the feature should not be
        # able to use the API.
        def initialize(*args, **options)
          super(*T.unsafe(["PROJECTS_NEW_DISABLED", "Projects New are not yet enabled for Enterprise", *args]), **options)
        end
      end
    end
  end
end
