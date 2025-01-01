# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module IRequest
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.returns(Integer) }
      def pull_request_id; end
    end
  end
end
