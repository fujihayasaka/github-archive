# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateRef < Platform::Mutations::Base
      include Helpers::GitRefs

      description "Create a new Git Ref."
      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The Node ID of the Repository to create the Ref in.", required: true, loads: Objects::Repository
      argument :name, String, "The fully qualified name of the new Ref (ie: `refs/heads/my_new_branch`).", required: true
      argument :oid, Scalars::GitObjectID, "The GitObjectID that the new Ref shall target. Must point to a commit.", required: true

      field :ref, Objects::Ref, "The newly created ref.", null: true

      def self.async_api_can_modify?(permission, repository:, oid:, **_)
        permission.async_owner_if_org(repository).then do |org|
          permission.access_allowed?(:create_ref_v2,
            repo: repository,
            current_org: org,
            before_oid: GitHub::NULL_OID,
            after_oid: oid,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      def resolve(repository:, name:, oid:)
        assert_repo_is_writable(repository)
        validate_name(name)
        proposed_target = fetch_target(repository, oid)
        if creating_branch?(name)
          enforce_target_type_policy(proposed_target)
        end
        created_ref = create_ref(repository, name, proposed_target)
        { ref: created_ref }
      end

      private

      BRANCH_REF_PREFIX = "refs/heads/"
      TAG_REF_PREFIX = "refs/tags/"

      # Ensure that the given string is valid as a fully qualified git ref
      # name.  `Rugged::Reference.valid_name?` is close but not strict
      # enough since it allows arbitrary namespaces.  We want to prohibit
      # reserved and unrecognized ref namespaces (i.e. everything other
      # than heads/tags).
      def validate_name(name)
        unless Rugged::Reference.valid_name?(name) && (creating_branch?(name) || creating_tag?(name))
          raise Errors::Unprocessable.new("#{name.inspect} is not a valid ref name.")
        end
      end

      def creating_branch?(name)
        name.start_with?(BRANCH_REF_PREFIX)
      end

      def creating_tag?(name)
        name.start_with?(TAG_REF_PREFIX)
      end

      def create_ref(repository, name, target)
        reflog_data = build_reflog_hash(context: context, via: "CreateRef mutation")
        repository.extended_refs.create(name, target, context[:viewer], reflog_data: reflog_data)
      rescue Git::Ref::ExistsError
        raise Errors::Unprocessable.new("A ref named #{name.inspect} already exists in the repository.")
      rescue Git::Ref::HookFailed => e
        raise Errors::Unprocessable.new("Could not create ref because a Git pre-receive hook failed: #{e.message}.")
      rescue Git::Ref::InvalidName
        raise Errors::Unprocessable.new("#{name.inspect} is not a valid ref name.")
      rescue Git::Ref::ProtectedBranchUpdateError => e
        raise Errors::Unprocessable.new("Cannot create ref because of rule violations: #{e.result.message}")
      rescue Git::Ref::RepositoryRuleViolationError => e
        raise Errors::Unprocessable.new(e.detailed_message)
      rescue Git::Ref::UpdateFailed => e
        # Not really expected to get here, something got past validation.  Can
        # trigger this condition by e.g. setting branch ref to blob oid.
        Failbot.report(e, "gh.repo.id": repository.id, "git.commit.oid": target.oid)
        raise Errors::Unprocessable.new("Ref cannot be created.")
      end
    end
  end
end
