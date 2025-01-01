# typed: true
# frozen_string_literal: true

module Git
  module Branch
    class Update < Git::Ref::Update
      extend T::Sig

      attr_reader :force, :pull_request

      # Public: Representation of a single branch update
      #
      # policy_commit_oid            - String OID of the reference state for policy check
      # force                        - Boolean: whether updates that are not
      #                                fast-forwardable should be allowed.
      # allow_deletion_policy_bypass - Boolean: whether updates that are deletions should
      #                                bypass the branch deletion policy.
      #
      # See Git::Ref::Update#initialize for the list of options
      def initialize(policy_commit_oid: nil, force: true, allow_deletion_policy_bypass: false, pull_request: nil, **args)
        @force = force
        @policy_commit_oid = policy_commit_oid
        @allow_deletion_policy_bypass = allow_deletion_policy_bypass
        @pull_request = pull_request
        super(**T.unsafe(args))
      end

      # When squashing before merging, the policy commit is the previous merge
      # commit SHA, referenced in PullRequest#merge_commit_sha, that is rewritten
      # into a squashed commit.
      #
      # Returns a Commit.
      def rule_commit
        @rule_commit ||= repository.commits.find(policy_commit_oid)
      end

      def policy_commit_oid
        @policy_commit_oid || @after_oid
      end

      # When renaming a branch, we allow the update to bypass the branch deletion policy
      def allow_deletion_policy_bypass?
        @allow_deletion_policy_bypass
      end

      protected

      def validate_attributes
        super
        GitRPC::Util.ensure_valid_full_sha1(policy_commit_oid)
        enforce_fast_forward_policy
      end

      def state
        super + [policy_commit_oid]
      end

      private

      def enforce_fast_forward_policy
        return if creation? || deletion? # only want to check for "true" updates
        return if force
        if !repository.rpc.descendant_of?(after_oid, before_oid)
          raise ::Git::Ref::NotFastForward
        end
      end
    end
  end
end
