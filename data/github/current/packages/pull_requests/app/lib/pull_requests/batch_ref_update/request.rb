# typed: strict
# frozen_string_literal: true

module PullRequests
  module BatchRefUpdate
    module Request
      include Kernel
      extend T::Helpers
      abstract!
      sealed!

      sig { abstract.returns(Integer) }
      def pull_request_id; end

      sig { returns(String) }
      def identifier
        "#{pull_request_id}|#{ref_name}"
      end

      sig { abstract.returns(String) }
      def ref_name; end

      class Eligible < T::Struct
        include Request

        const :pull_request_id, Integer
        const :ref_name, String
        const :before_sha, T.nilable(String)
        const :after_sha, String
      end

      # Requests should be eligible if the following things are true:
      #  * The current state of the ref is valid, head/base commits exist.
      #  * The update hasn't been performed yet.

      class Ineligible < T::Struct
        include Request

        const :pull_request_id, Integer
        const :ref_name, String
        const :before_sha, T.nilable(String)
        const :after_sha, T.nilable(String)
        const :reason, Enums::Failures
      end
    end
  end
end
