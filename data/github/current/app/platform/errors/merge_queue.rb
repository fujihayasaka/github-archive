# typed: true
# frozen_string_literal: true

module Platform
  module Errors
    module MergeQueue
      # These error messages are parsed by Heaven
      # (https://github.com/github/heaven/blob/15da3d05d4e322ea19a9e1c4773c2a5524689b66/app/lib/external/github/merge_queue.rb#L465-L467)
      # so ensure they don't change without changing Heaven, too.

      class NotEnabled < Errors::Unprocessable
        def initialize
          super "Merge queues are not enabled."
        end
      end

      class NotEnabledForRepository < Errors::Unprocessable
        def initialize(repository)
          super "Merge queues are not enabled for #{repository.name_with_display_owner}."
        end
      end

      class NotFoundForBranch < Errors::Unprocessable
        def initialize(branch)
          super "No merge queue found for branch '#{branch}'"
        end
      end

      class NotRemovedFromQueueBecauseGroupLocked < Errors::Unprocessable
        def initialize(pull_request)
          super "Failed to remove PR: merge group locked! ##{pull_request.number} \"#{pull_request.title}\"".truncate(100)
        end
      end

      class PullRequestHeadOidMismatch < Errors::Unprocessable
        def initialize(pull_request)
          super "Failed to add PR ##{pull_request.number}: expected head oid does not match the current head oid"
        end
      end

      class NotRemovedFromQueue < Errors::Unprocessable
        def initialize(pull_request)
          super "Failed to remove PR ##{pull_request.number} \"#{pull_request.title}\"".truncate(100)
        end
      end

      class DeploymentsNotRequired < Errors::Unprocessable
        def initialize(branch)
          super "Deployments are not required for merge queue branch '#{branch}', "\
                "merges will happen automatically."
        end
      end
    end
  end
end
