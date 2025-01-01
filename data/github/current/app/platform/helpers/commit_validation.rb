# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module CommitValidation
      include Kernel

      def find_commit!(repo, sha)
        if sha && commit_oid = repo.ref_to_sha(sha)
          repo.commits.find(commit_oid)
        else
          raise Platform::Errors::Validation.new("No commit found for SHA: #{sha}")
        end
      rescue GitRPC::InvalidObject, GitRPC::ObjectMissing
        raise Platform::Errors::Validation.new("No commit found for SHA: #{sha}")
      end
    end
  end
end
