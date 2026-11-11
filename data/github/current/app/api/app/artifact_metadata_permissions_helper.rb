# typed: strict
# frozen_string_literal: true

module Api::App::ArtifactMetadataPermissionsHelper
  extend T::Helpers

  requires_ancestor { ::Api::App }

  class RepoErrorResponse < T::Struct
    prop :cause, String
    prop :repositories, T::Array[String]
  end

  class RepositoryPermissionResult < T::Struct
    prop :visible, T::Array[Integer]
    prop :invisible, T::Array[Integer]

    sig { returns T::Boolean }
    def no_repositories_visible?
      visible.empty?
    end
  end

  class ErrNoRepositoriesVisible < StandardError
    sig { void }
    def initialize
      super("Actor does not have visibility on any requested repositories")
    end
  end

  class ErrNoRepoReadAccess < StandardError
    sig { returns T::Array[Integer] }
    attr_reader :repo_ids

    sig { params(repo_ids: T::Array[Integer]).void }
    def initialize(repo_ids)
      @repo_ids = repo_ids
      super("Actor does not have read access to any of the requested repositories: #{repo_ids.join(', ')}")
    end
  end

  class ErrNoRepositoryWriteAccess < StandardError
    sig { returns T::Array[String] }
    attr_reader :repo_names

    sig { params(repo_names: T::Array[String]).void }
    def initialize(repo_names)
      @repo_names = repo_names
      super("Actor does not have write access to repositories #{repo_names.join(', ')}")
    end

    sig { returns(RepoErrorResponse) }
    def response_message
      RepoErrorResponse.new(
        cause: "Actor does not have the artifact metadata write permission on one or more repositories",
        repositories: repo_names
      )
    end
  end

  class ErrMismatchingRepositories < StandardError
    sig { returns Integer }
    attr_reader :org_id
    sig { returns T::Array[Integer] }
    attr_reader :requested_repo_ids
    sig { returns T::Array[Integer] }
    attr_reader :found_repo_ids

    sig { params(org_id: Integer, requested_repo_ids: T::Array[Integer], found_repo_ids: T::Array[Integer]).void }
    def initialize(org_id, requested_repo_ids, found_repo_ids)
      @org_id = org_id
      @requested_repo_ids = requested_repo_ids
      @found_repo_ids = found_repo_ids
      super("Mismatch between requested repositories and repositories belonging to org #{org_id}. Requested: #{requested_repo_ids}, Found: #{found_repo_ids}")
    end

    sig { returns(RepoErrorResponse) }
    def response_message
      missing_repo_ids = requested_repo_ids - found_repo_ids
      missing_repo_names = Repository.where(id: missing_repo_ids).pluck(:name)
      RepoErrorResponse.new(
        cause: "One or more repositories do not exist",
        repositories: missing_repo_names
      )
    end
  end

  class ErrNoReposFoundInOrg < StandardError
    sig { returns Integer }
    attr_reader :org_id

    sig { params(org_id: Integer).void }
    def initialize(org_id)
      @org_id = org_id
      super("No repositories found for org #{org_id}")
    end

    sig { returns(RepoErrorResponse) }
    def response_message
      RepoErrorResponse.new(
        cause: "No repositories found for the organization",
        repositories: []
      )
    end
  end

  class ErrTokenMissingWriteArtifactMetadataPerm < StandardError
    sig { void }
    def initialize
      super("Token does not have write_artifact_metadata permission")
    end

    sig { returns(String) }
    def response_message
      "App token does not have write_artifact_metadata permission"
    end
  end

  class ErrNoArtifactLinkage < StandardError
    sig { void }
    def initialize
      super("No artifact linkage found for the provided deployment parameters")
    end

    sig { returns(String) }
    def response_message
      "no deployment records found"
    end
  end

  class ErrNoDeploymentsAuthorized < StandardError
    sig { void }
    def initialize
      super("Actor is unauthorized against all deployments")
    end
  end

  class ErrNoDeploymentsFound < StandardError
    sig { void }
    def initialize
      super("Actor has no visibility to any deployment repositories")
    end
  end

  class AuthorizationEntry < T::Struct
    prop :current_records, T::Array[ArtifactDeploymentRecord]
    prop :proposed_records, T::Array[DeploymentTemplate]
  end

  class AuthorizationResult < T::Struct
    prop :authorized, AuthorizationEntry
    prop :unauthorized, AuthorizationEntry
    prop :not_found, AuthorizationEntry
  end

  sig { params(records: T::Array[ArtifactDeploymentRecord], deployment_manager: DeploymentTemplateManager, allow_partial_success: T::Boolean, metrics: SetClusterRecordMetrics).returns(AuthorizationResult) }
  def authorize_cluster_set_records!(records, deployment_manager, allow_partial_success, metrics)
    # Create an array of repository IDs from existing records and the artifact linkage associated with proposed records
    repo_ids = records.map { |record| T.must(record.artifact_metadata).repository_id }.compact.uniq

    if deployment_manager.deployment_templates.present?
      new_record_linkage = []
      begin
        tma_request_start = GitHub::Dogstats.monotonic_time
        new_record_linkage = deployment_manager.set_artifact_linkage_and_return_repository_ids(metrics)
        metrics.publish_distribution_metric("tma_request_time", GitHub::Dogstats.duration(tma_request_start))
      rescue => e
        GitHub.logger.info("Error encountered while setting artifact linkage for deployment records: #{e.message}")
        raise
      end

      # If no repo and attestation IDs are found for the provided deployments, we have not found a valid way to link
      # the proposed deployment records to artifacts and repositories
      if new_record_linkage.blank?
        GitHub.logger.info("No repository and attestation linkages found for the provided deployment parameters, cannot create deployment record")
        raise ErrNoArtifactLinkage.new
      end
      # return the set union of elements to remove duplicates
      repo_ids |= Array(new_record_linkage)
    end

    permission_result = begin
      check_repo_permissions_against_token!(repo_ids, deployment_manager.org, !allow_partial_success)
    rescue => e
      GitHub.logger.info("Permission check failed for cluster set records: #{e.message}")
      raise
    end

    permission_error = permission_result[:error]
    unauthorized_repo_ids = permission_result[:unauthorized_repo_ids] || []
    not_found_repo_ids = permission_result[:not_found_repo_ids] || []
    # In "strict mode" (non-partial success), we would expect check_repo_permissions_against_token to raise
    # an error instead of returning a set of authorized repositories and an error message. If we receive an error message here,
    # it indicates that the permission check function is not correctly enforcing strict permissions for cluster set records
    if !allow_partial_success
      if permission_error.present?
        GitHub.logger.error("Permission check returned both authorized and unauthorized repositories unexpectedly: #{permission_error}")
        raise "Unexpected success in strict permission check for cluster set records, expected an error to be raised if any repository is not accessible with the current token/installation permissions"
      end
      return AuthorizationResult.new(
        authorized: AuthorizationEntry.new(
          current_records: records,
          proposed_records: deployment_manager.deployment_templates.values.flatten
        ),
        unauthorized: AuthorizationEntry.new(
          current_records: [],
          proposed_records: []
        ),
        not_found: AuthorizationEntry.new(
          current_records: [],
          proposed_records: []
        )
      )
    end

    # When allow_partial_success is true, permission_error might be present but we continue with filtering
    filtered_repo_ids = permission_result[:filtered_repo_ids]
    authorization_result = build_categorized_authorization_result(permission_error, repo_ids, filtered_repo_ids, records, deployment_manager.deployment_templates.values.flatten, unauthorized_repo_ids, not_found_repo_ids)

    # Add unresolvable_templates that had no link through TMA or github_repository param
    deployment_manager.unresolvable_templates.each do |template|
      authorization_result.not_found.proposed_records << template
    end

    # If partial_success is enabled and all deployments were rejected, raise error to be handled by caller
    authorized_current_records = authorization_result.authorized.current_records
    authorized_proposed_records = authorization_result.authorized.proposed_records
    if authorized_proposed_records.empty? && authorized_current_records.empty?
      not_found_templates = authorization_result.not_found.proposed_records
      if not_found_templates.any?
        raise ErrNoDeploymentsFound.new
      end
      not_authorized = authorization_result.unauthorized.proposed_records

      if not_authorized.any?
        raise ErrNoDeploymentsAuthorized.new
      end
    end

    authorization_result
  end

  sig { params(error: T.nilable(StandardError), all_repo_ids: T::Array[Integer], authorized_repo_ids: T::Array[Integer], records: T::Array[ArtifactDeploymentRecord], deployment_templates: T::Array[DeploymentTemplate], unauthorized_repo_ids: T::Array[Integer], not_found_repo_ids: T::Array[Integer]).returns(AuthorizationResult) }
  def build_categorized_authorization_result(error, all_repo_ids, authorized_repo_ids, records, deployment_templates, unauthorized_repo_ids = [], not_found_repo_ids = [])
    # Group records by repository ID
    records_map = records.group_by { |r| T.must(r.artifact_metadata).repository_id }

    # Partition records into authorized and rejected based on authorized_repo_ids
    authorized_records = authorized_repo_ids.flat_map { |id| records_map[id] || [] }.compact
    rejected_records = (records_map.keys - authorized_repo_ids).flat_map { |id| records_map[id] || [] }.compact

    # Further partition rejected records into unauthorized and not_found based on provided repo IDs
    unauthorized_records_list = []
    not_found_records_list = []

    if unauthorized_repo_ids.any? || not_found_repo_ids.any?
      # Use explicit categorization when provided
      unauthorized_records_list = rejected_records.select { |r| unauthorized_repo_ids.include?(T.must(r.artifact_metadata).repository_id) }
      not_found_records_list = rejected_records.select { |r| not_found_repo_ids.include?(T.must(r.artifact_metadata).repository_id) }
    else
      # Fallback to error type-based categorization for backward compatibility
      case error
      when ErrNoRepositoryWriteAccess
        GitHub.logger.info("Actor does not have write access to any associated repositories for deployment record creation")
        unauthorized_records_list = rejected_records
      when ErrNoRepoReadAccess
        not_found_records_list = rejected_records
      when nil
        # All items are authorized, no rejections
      else
        raise "Unhandled error type #{error.class} in build_categorized_authorization_result"
      end
    end

    # Partition templates based on their linkage repository authorization status
    authorized_templates = []
    unauthorized_templates = []
    not_found_templates = []

    deployment_templates.each do |template|
      authorized_linkage_entries = template.linkage.repo_and_attestation_ids&.select { |entry| authorized_repo_ids.include?(entry[:repository_id]) } || []
      rejected_linkage_entries = template.linkage.repo_and_attestation_ids&.reject { |entry| authorized_repo_ids.include?(entry[:repository_id]) } || []

      authorized_template, rejected_template = create_templates_with_filtered_linkage(template, authorized_linkage_entries, rejected_linkage_entries)

      # If template has any authorized linkage repositories, include it in authorized with filtered linkage
      if authorized_template.present?
        authorized_templates << authorized_template
      end

      # If template has any rejected linkage repositories, categorize based on error type
      if rejected_template.present?
        if unauthorized_repo_ids.any? || not_found_repo_ids.any?
          # Use explicit categorization: split rejected linkage into unauthorized and not_found
          rejected_linkage_unauthorized = rejected_linkage_entries.select { |entry| unauthorized_repo_ids.include?(entry[:repository_id]) }
          rejected_linkage_not_found = rejected_linkage_entries.select { |entry| not_found_repo_ids.include?(entry[:repository_id]) }

          if rejected_linkage_unauthorized.any?
            GitHub.logger.info("Actor does not have write access to any associated repositories for deployment record creation")
            # Create template with only unauthorized linkage
            unauthorized_template = DeploymentTemplate.new(
              template.owner_id,
              template.artifact_template,
              {
                cluster: template.cluster,
                deployment_name: template.deployment_name,
                logical_environment: template.logical_environment,
                physical_environment: template.physical_environment,
                runtime_risks: template.runtime_risks,
                tags: template.tags,
                github_repository: template.github_repository,
                status: template.status
              }
            )
            unauthorized_template.linkage.repo_and_attestation_ids = rejected_linkage_unauthorized
            unauthorized_templates << unauthorized_template
          end

          if rejected_linkage_not_found.any?
            # Create template with only not_found linkage
            not_found_template = DeploymentTemplate.new(
              template.owner_id,
              template.artifact_template,
              {
                cluster: template.cluster,
                deployment_name: template.deployment_name,
                logical_environment: template.logical_environment,
                physical_environment: template.physical_environment,
                runtime_risks: template.runtime_risks,
                tags: template.tags,
                github_repository: template.github_repository,
                status: template.status
              }
            )
            not_found_template.linkage.repo_and_attestation_ids = rejected_linkage_not_found
            not_found_templates << not_found_template
          end
        else
          # Fallback to error type-based categorization
          case error
          when ErrNoRepositoryWriteAccess
            GitHub.logger.info("Actor does not have write access to any associated repositories for deployment record creation")
            unauthorized_templates << rejected_template
          when ErrNoRepoReadAccess
            not_found_templates << rejected_template
          when nil
            # Should not happen if there are rejected repositories
            GitHub.logger.warn("Rejected linkage repositories found but no error set for template: #{template}")
          else
            raise "Unhandled error type #{error.class} in build_categorized_authorization_result"
          end
        end
      end
    end

    AuthorizationResult.new(
      authorized: AuthorizationEntry.new(current_records: authorized_records, proposed_records: authorized_templates),
      unauthorized: AuthorizationEntry.new(current_records: unauthorized_records_list, proposed_records: unauthorized_templates),
      not_found: AuthorizationEntry.new(current_records: not_found_records_list, proposed_records: not_found_templates)
    )
  end

  sig { params(template: DeploymentTemplate, authorized_linkage_entries: T::Array[T::Hash[String, T.untyped]], rejected_linkage_entries: T::Array[T::Hash[String, T.untyped]]).returns([T.nilable(DeploymentTemplate), T.nilable(DeploymentTemplate)]) }
  private def create_templates_with_filtered_linkage(template, authorized_linkage_entries, rejected_linkage_entries)
    # Create authorized template if there are any authorized linkage entries
    authorized_template = if authorized_linkage_entries.any?
      filtered_template = DeploymentTemplate.new(
        template.owner_id,
        template.artifact_template,
        {
          cluster: template.cluster,
          deployment_name: template.deployment_name,
          logical_environment: template.logical_environment,
          physical_environment: template.physical_environment,
          runtime_risks: template.runtime_risks,
          tags: template.tags,
          github_repository: template.github_repository,
          status: template.status
        }
      )
      filtered_template.linkage.repo_and_attestation_ids = T.cast(authorized_linkage_entries, T::Array[{ artifact_metadata_id: T.nilable(Integer), attestation_id: T.nilable(Integer), repository_id: Integer }])
      filtered_template
    end

    # Create rejected template if there are any rejected linkage entries
    rejected_template = if rejected_linkage_entries.any?
      filtered_template = DeploymentTemplate.new(
        template.owner_id,
        template.artifact_template,
        {
          cluster: template.cluster,
          deployment_name: template.deployment_name,
          logical_environment: template.logical_environment,
          physical_environment: template.physical_environment,
          runtime_risks: template.runtime_risks,
          tags: template.tags,
          github_repository: template.github_repository,
          status: template.status
        }
      )
      filtered_template.linkage.repo_and_attestation_ids = T.cast(rejected_linkage_entries, T::Array[{ artifact_metadata_id: T.nilable(Integer), attestation_id: T.nilable(Integer), repository_id: Integer }])
      filtered_template
    end

    [authorized_template, rejected_template]
  end

  sig { params(repo_ids: T::Array[Integer], org: Organization, strict: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def check_repo_permissions_against_token!(repo_ids, org, strict)
    if strict
      # Strict mode: raise errors immediately
      check_repo_permissions_strict!(repo_ids, org)
    else
      # Non-strict mode: return errors in hash for partial_success handling
      check_repo_permissions_for_partial_success!(repo_ids, org)
    end
  end

  sig { params(repo_ids: T::Array[Integer], org: Organization).returns(T::Hash[Symbol, T.untyped]) }
  def check_repo_permissions_strict!(repo_ids, org)
    found_repo_ids = Repository.where(id: repo_ids, owner_id: org.id).pluck(:id)
    if found_repo_ids.empty?
      GitHub.logger.info("No requested repositories found for the organization", "gh.org.id" => org.id, "gh.requested_repo_ids" => repo_ids)
      raise ErrMismatchingRepositories.new(org.id, repo_ids, found_repo_ids)
    end

    if found_repo_ids.sort != repo_ids.sort
      GitHub.logger.info("Mismatch between requested repositories and repositories belonging to org when creating deployment records", "gh.org.id" => org.id, "gh.requested_repo_ids" => repo_ids, "gh.found_repo_ids" => found_repo_ids)
      raise ErrMismatchingRepositories.new(org.id, repo_ids, found_repo_ids)
    end

    installation = artifact_metadata_determine_installation
    result = filter_repos_by_visibility(org, found_repo_ids, installation)
    if result.no_repositories_visible?
      GitHub.logger.error("No repositories visible to actor when creating deployment records")
      raise ErrNoRepositoriesVisible.new
    end

    if installation.present?
      # We know that the installation can at the very least see these repositories.
      # Because installation tokens are created by picking permissions that are then applied to all repositories
      # specified token, we can check if the installation has the required permission to write artifact metadata for all visible repositories.
      visible_repos = result.visible
      # Fast path: Check if actor has org-wide artifact metadata write access using centralized role
      if access_allowed?(:write_org_artifact_metadata, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
        if result.invisible.any?
          raise ErrNoRepoReadAccess.new(result.invisible)
        end
        return { filtered_repo_ids: visible_repos, error: nil, unauthorized_repo_ids: [], not_found_repo_ids: [] }
      end

      if !token_has_artifact_metadata_permission?(installation)
        GitHub.logger.info("Token does not have write artifact metadata permission required for deployment record creation")
        raise ErrTokenMissingWriteArtifactMetadataPerm.new
      end

      accessible_repo_ids = get_accessible_repositories_for_installation(installation, org, visible_repos).map(&:id)
      repos_without_access = visible_repos - accessible_repo_ids
      if repos_without_access.any?
        repo_names = Repository.where(id: repos_without_access).pluck(:name)
        GitHub.logger.info("Actor does not have write access to any associated repositories for deployment record creation", "gh.repo.names" => repo_names)
        raise ErrNoRepositoryWriteAccess.new(repo_names)
      end

      if result.invisible.any?
        raise ErrNoRepoReadAccess.new(result.invisible)
      end

      return { filtered_repo_ids: accessible_repo_ids, error: nil, unauthorized_repo_ids: [], not_found_repo_ids: [] }
    end

    # Fallback to regular user case - check write access
    # Check if they have write access to all visible repos
    writable_repo_ids = current_user.associated_repository_ids(
      repository_ids: result.visible,
      min_action: :write,
      organization: org
    )
    repos_without_access = result.visible - writable_repo_ids
    if repos_without_access.any?
      repo_names = Repository.where(id: repos_without_access).pluck(:name)
      GitHub.logger.info("Actor does not have write access to any associated repositories for deployment record creation", "gh.repo.names" => repo_names)
      raise ErrNoRepositoryWriteAccess.new(repo_names)
    end

    if result.invisible.any?
      raise ErrNoRepoReadAccess.new(result.invisible)
    end

    { filtered_repo_ids: writable_repo_ids, error: nil, unauthorized_repo_ids: [], not_found_repo_ids: [] }
  end

  sig { params(repo_ids: T::Array[Integer], org: Organization).returns(T::Hash[Symbol, T.untyped]) }
  def check_repo_permissions_for_partial_success!(repo_ids, org)
    found_repo_ids = Repository.where(id: repo_ids, owner_id: org.id).pluck(:id)
    if found_repo_ids.empty?
      GitHub.logger.info("No requested repositories found for the organization", "gh.org.id" => org.id, "gh.requested_repo_ids" => repo_ids)
      raise ErrMismatchingRepositories.new(org.id, repo_ids, found_repo_ids)
    end

    # Return repos not owned by org as "not found"
    not_owned_repo_ids = repo_ids - found_repo_ids
    if not_owned_repo_ids.any?
      GitHub.logger.info("Mismatch between requested repositories and repositories belonging to org when creating deployment records", "gh.org.id" => org.id, "gh.requested_repo_ids" => repo_ids, "gh.found_repo_ids" => found_repo_ids)
    end

    installation = artifact_metadata_determine_installation
    result = filter_repos_by_visibility(org, found_repo_ids, installation)
    if result.no_repositories_visible?
      GitHub.logger.error("No repositories visible to actor when creating deployment records")
      raise ErrNoRepositoriesVisible.new
    end


    if installation.present?
      visible_repos = result.visible
      if access_allowed?(:write_org_artifact_metadata, resource: org, allow_integrations: true, allow_user_via_granular_actor: true)
        not_found_repo_ids = not_owned_repo_ids + result.invisible
        # If the actor has org-wide access, we can skip the more expensive checks below
        return { filtered_repo_ids: visible_repos, error: nil, unauthorized_repo_ids: [], not_found_repo_ids: not_found_repo_ids }
      end

      # Fallback: Check if actor has access to the specific repos
      # Raise an error if the installation token does not have the required permission
      if !token_has_artifact_metadata_permission?(installation)
        GitHub.logger.info("Token does not have write artifact metadata permission required for deployment record creation")
        raise ErrTokenMissingWriteArtifactMetadataPerm.new
      end

      accessible_repo_ids = get_accessible_repositories_for_installation(installation, org, visible_repos).map(&:id)
      repos_without_access = visible_repos - accessible_repo_ids

      if repos_without_access.any? || result.invisible.any?
        return {
          filtered_repo_ids: accessible_repo_ids,
          error: nil,
          unauthorized_repo_ids: repos_without_access,
          not_found_repo_ids: result.invisible
        }
      end

      return { filtered_repo_ids: accessible_repo_ids, error: nil, unauthorized_repo_ids: [], not_found_repo_ids: [] }
    end

    # Fallback to regular user case
    writable_repo_ids = current_user.associated_repository_ids(
      repository_ids: result.visible,
      min_action: :write,
      organization: org
    )
    repos_without_access = result.visible - writable_repo_ids

    if repos_without_access.any? || result.invisible.any?
      return {
        filtered_repo_ids: writable_repo_ids,
        error: nil,
        unauthorized_repo_ids: repos_without_access,
        not_found_repo_ids: result.invisible
      }
    end

    { filtered_repo_ids: writable_repo_ids, error: nil, unauthorized_repo_ids: [], not_found_repo_ids: [] }
  end

  sig { params(granular_actor: T.untyped).returns(T::Boolean) }
  def token_has_artifact_metadata_permission?(granular_actor = nil)
    return false if granular_actor.nil?
    permissions = granular_actor.permissions
    Ability.can_at_least?(:write, permissions["artifact_metadata"])
  end

  private

  sig { params(org: Organization, repo_ids: T::Array[Integer], installation: T.untyped).returns(RepositoryPermissionResult) }
  def filter_repos_by_visibility(org, repo_ids, installation = nil)
    # In order to set the read_artifact_metadata or write_artifact_metadata permissions for a repository with a
    # fine grained permission model, the actor must also have get_repo permissions for that repository. The get_repo
    # permission is required before setting any other permission on the repository, so we check that first to filter
    # which repositories are visible to the actor.
    if installation.present?
      accessible_repos = get_accessible_repositories_for_installation(installation, org, repo_ids).map(&:id)
      visible_repos = accessible_repos
    else
      visible_repos = current_user.associated_repository_ids(
        repository_ids: repo_ids,
        min_action: :read,
        organization: org
      )
    end

    return RepositoryPermissionResult.new(visible: [], invisible: repo_ids) if visible_repos.empty?

    hidden_repos = repo_ids - visible_repos
    RepositoryPermissionResult.new(visible: visible_repos, invisible: hidden_repos)
  end

  sig { returns(T.nilable(T.any(IntegrationInstallation, ScopedIntegrationInstallation, UserProgrammaticAccessGrant, OrganizationProgrammaticAccessGrant))) }
  def artifact_metadata_determine_installation
    if current_user.is_a?(Bot)
      current_user.installation
    elsif current_user.using_auth_via_granular_actor?
      current_user.programmatic_access&.grant
    elsif current_user.is_a?(IntegrationInstallation)
      current_user
    else
      nil
    end
  end

  sig { params(installation: T.untyped, org: Organization, repo_ids: T::Array[Integer]).returns(T::Array[Repository]) }
  def get_accessible_repositories_for_installation(installation, org, repo_ids)
    case installation
    # GitHub App installations (bot or scoped integration) that have access to specific repositories
    when IntegrationInstallation, ScopedIntegrationInstallation
      installation.repositories.where(id: repo_ids, owner_id: org.id).to_a
    # Organization Programmatic Access Grants with configurable repository selection
    when OrganizationProgrammaticAccessGrant
      case installation.repository_selection.to_s
      # Access limited to a subset of repositories explicitly selected in the grant configuration
      when "subset"
        installation.repositories.where(id: repo_ids, owner_id: org.id).to_a
      # Access granted to all repositories in the organization
      when "all"
        org.repositories.to_a
      # Unknown or invalid repository selection mode
      else
        []
      end
    # Unrecognized installation type - no access granted
    else
      []
    end
  end
end
