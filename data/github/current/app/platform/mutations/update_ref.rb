# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateRef < Platform::Mutations::Base
      include Helpers::GitRefs

      description "Update a Git Ref."
      minimum_accepted_scopes ["public_repo"]

      argument :ref_id, ID, "The Node ID of the Ref to be updated.", required: true, loads: Objects::Ref
      argument :oid, Scalars::GitObjectID, "The GitObjectID that the Ref shall be updated to target.", required: true
      argument :force, Boolean, "Permit updates of branch Refs that are not fast-forwards?", default_value: false, required: false

      field :ref, Objects::Ref, "The updated Ref.", null: true

      def self.async_api_can_modify?(permission, ref:, oid:, **_)
        repository = ref.repository
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:update_ref_v2,
            repo: repository,
            current_org: org,
            ref_name: ref.name,
            before_oid: ref.target.oid,
            after_oid: oid,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(ref:, oid:, force:)
        repo = ref.repository
        assert_repo_is_writable(repo)
        proposed_oid = oid
        proposed_target = fetch_target(repo, proposed_oid)
        if ref.branch?
          enforce_target_type_policy(proposed_target)
        end

        { ref: update_ref(ref, proposed_target, force) }
      end

      private

      def update_ref(ref, target, force)
        reflog_data = build_reflog_hash(context: context, via: "UpdateRef mutation")
        ref.update(target, context[:viewer], reflog_data: reflog_data, force: force)
      rescue Git::Ref::NotFastForward
        raise Errors::Unprocessable.new("Refusing to perform non-fast-foward update when `force=false`.")
      rescue Git::Ref::ProtectedBranchUpdateError => e
        raise Errors::Unprocessable.new("Branch is protected: #{e.result.message}")
      rescue Git::Ref::InvalidName => e
        raise Errors::Unprocessable.new(e.message)
      rescue Git::Ref::RepositoryRuleViolationError => e
        raise Errors::Unprocessable.new(e.detailed_message)
      rescue Git::Ref::HookFailed => e
        raise Errors::Unprocessable.new("A Git pre-receive hook failed: #{e.message}.")
      rescue Git::Ref::ComparisonMismatch
        raise Errors::Unprocessable.new("Reference cannot be updated.")
      end
    end
  end
end
