# typed: false
# frozen_string_literal: true

module Platform
  module Helpers
    # Common functionality for git ref mutations.
    module GitRefs

      # Validate that the given OID is present in the repository and
      # return its target or raise GitRPC::ObjectMissing.
      def fetch_target(repository, oid)
        repository.objects.read(oid)
      rescue GitRPC::ObjectMissing
        raise Errors::NotFound.new("Object with oid #{oid.inspect} does not exist in the repository.")
      end

      def enforce_target_type_policy(proposed_target)
        if !proposed_target.instance_of?(Commit)
          raise Errors::Unprocessable.new("For branch refs, oid must point to a Commit (got #{proposed_target.class}).")
        end
      end

      def assert_repo_is_writable(repository)
        if repository.empty?
          raise Errors::Unprocessable.new("Git Repository is empty.")
        end
        if repository.locked_on_migration?
          raise Errors::Unprocessable::RepositoryMigration.new
        end
        if repository.archived?
          raise Errors::Unprocessable::RepositoryArchived.new
        end
      end

      # Build a hash of additional context data to be stored in the
      # git reflog.  See Git::Ref#write_ref.
      def build_reflog_hash(context:, via:)
        {
          real_ip: context[:ip],
          # disabled linter since reflog is not customer facing
          user_login: context[:viewer].login, # rubocop:disable GitHub/DoNotAllowLogin
          user_agent: context[:user_agent],
          from: GitHub.context[:from],
          via: via,
        }
      end
    end
  end
end
