# typed: strict
# frozen_string_literal: true

module OIDC
  module UseImmutableSubjectHelper
    extend T::Helpers

    # Resolves the effective use_immutable_subject value for a repository.
    # Truth matrix from ADR: repo-level true wins, else org-level, else false.
    # This helper is shared by the REST API and the UI controllers.
    sig { params(repo: Repository, configuration: T.nilable(T::Hash[String, T.untyped])).returns(T::Boolean) }
    def resolve_use_immutable_subject(repo:, configuration: nil)
      configuration ||= RepositoryActionsOIDCConfig.get_configurations(repo.id)

      # Check repo-level setting first
      repo_setting = configuration[RepositoryActionsOIDCConfig::KEY_USE_IMMUTABLE_SUBJECT]
      return true if repo_setting == true

      # Fall back to org-level setting
      org_id = repo.organization_id
      if org_id
        template = OrganizationOIDCSubClaimTemplate.get_template_for_org(org_id)
        return true if template&.use_immutable_subject
      end

      false
    end
  end
end
