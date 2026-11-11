# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteRef < Platform::Mutations::Base
      include Helpers::GitRefs

      description "Delete a Git Ref."
      minimum_accepted_scopes ["public_repo"]

      argument :ref_id, ID, "The Node ID of the Ref to be deleted.", required: true, loads: Objects::Ref

      def self.async_api_can_modify?(permission, ref:, **_)
        repository = ref.repository
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:delete_ref,
            resource: repository,
            current_repo: repository,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(ref:)
        assert_repo_is_writable(ref.repository)
        reflog_data = build_reflog_hash(context: context, via: "DeleteRef mutation")
        ref.delete(context[:viewer], reflog_data: reflog_data)
        {}
      rescue Git::Ref::ProtectedBranchUpdateError => e
        raise Errors::Unprocessable.new("Branch is protected: #{e.result.message}.")
      rescue Git::Ref::RepositoryRuleViolationError => e
        raise Errors::Unprocessable.new(e.detailed_message)
      rescue Git::Ref::HookFailed => e
        raise Errors::Unprocessable.new("A Git pre-receive hook failed: #{e.message}.")
      rescue Git::Ref::ComparisonMismatch
        raise Errors::Unprocessable.new("Reference does not exist.")
      end
    end
  end
end
