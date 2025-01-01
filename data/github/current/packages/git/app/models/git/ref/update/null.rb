# typed: true
# frozen_string_literal: true

module Git
  class Ref
    class Update
      class Null
        attr_reader :repository, :refname, :before_oid

        # Public: Representation of a single ref update where we DO NOT
        # have an after_oid.  This can happen when there is not a valid
        # merge_commit_sha for a Pull Request, for example.
        #
        # repository - Repository the ref update is related to
        # refname    - String fully qualified ref name
        # before_oid - String OID of the current state of the ref
        def initialize(repository:, refname:, before_oid:)
          @repository = repository
          @refname = refname
          @before_oid = before_oid
        end

        # Create a Null Ref Update for the case where there is an invalid
        # merge commit for a pull request
        #
        # pull_request: PullRequest we want to create the ref update for
        def self.create_for_merge_conflict(pull_request)
          refname = "refs/heads/#{pull_request.base_ref_name}"
          new(repository: pull_request.repository,
            refname: refname,
            before_oid: pull_request.current_base_sha)
        end

        def after_oid
          raise ArgumentError, "after_oid is not available for a null ref update"
        end
      end
    end
  end
end
