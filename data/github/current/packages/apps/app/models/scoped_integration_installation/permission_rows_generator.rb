# typed: true
# frozen_string_literal: true

module ScopedIntegrationInstallation::PermissionRowsGenerator
  extend T::Helpers

  # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
  # See https://github.com/github/package-registry-team/issues/7344
  # The max packages that we can safely grant access to
  # https://github.com/github/ecosystem-apps/issues/3057
  TOO_MANY_PACKAGES_MSG = "Too many packages for installation. Please supply up to %s."

  InstallationCreatorTypes = T.type_alias do
    T.any(
      ScopedIntegrationInstallation::Creator,
      SiteScopedIntegrationInstallation::Creator,
      SiteScopedIntegrationInstallation::Creators::CodespaceWithOauthAccess,
      SiteScopedIntegrationInstallation::Creators::PrebuildCodespace
    )
  end

  PermissionRow = T.type_alias do
    T::Hash[Symbol, T.untyped]
  end

  # Represents a permission description used to reference a collection
  # of resource and their respective actions.
  # Ex. { "metadata" => :read, "contents" => "write" }
  PermissionsHash = T.type_alias do
    T::Hash[String, Symbol]
  end

  InstallationTarget = T.type_alias do
    T.any(User, Organization)
  end

  private

  def permission_row_for(actor:, subject:, action:, expires_at: nil)
    expires_at = expires_at.to_i if expires_at.present?

    ::Permissions::Service.installation_attributes_hash(
      actor: actor,
      subject: subject,
      action: action,
      expires_at: expires_at,
    )
  end

  def permission_rows_for_subjects(actor:, subjects:, permissions:, expires_at: nil, authorization_details: nil)
    return [] if permissions.empty?

    if authorization_details.present?
      resource_type = ScopedInstallations::AuthorizationDetails::ResourceType.for(subjects.first)

      authorization_details.set_selection_for(resource_type, ScopedInstallations::AuthorizationDetails::Selection::Subset)
      authorization_details.set_subject_ids_for(resource_type, subjects.map(&:ability_id))
      authorization_details.set_subject_types_and_actions_for(resource_type, permissions)
    end

    attributes = []

    permissions.each do |resource, action|
      subjects.each do |subject|
        collection = subject.resources.public_send(resource) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        attributes << Permissions::Service.installation_attributes_hash(
          actor: actor, subject: collection, action: action, expires_at: expires_at
        )
      end
    end

    attributes
  end

  def permission_rows_for_codespaces(integration:, installation:, codespaces:, expires_at: nil, authorization_details: nil)
    return [] unless Apps::Privileged.capable?(:static_installation_codespace_permissions, app: integration)

    permissions = Apps::Privileged.property(:static_installation_codespace_permissions, app: integration)
    return [] unless permissions

    permission_rows_for_subjects(
      actor: installation, subjects: codespaces, expires_at:,
      permissions: permissions, authorization_details:
    )
  end

  def permission_rows_for_workflow_runs(installation, repository, data)
    rows = []
    return rows unless data.key?("workflow_runs")

    # [ { "id" => 1, "permissions" => "codespaces_prebuild" => "write" } ]
    # => { 1 => "codespaces_prebuild" => :write }
    workflow_runs_and_permissions = data["workflow_runs"].each_with_object({}) do |workflow_run, hash|
      workflow_run_id = workflow_run["id"]
      permissions = workflow_run["permissions"].transform_values(&:to_sym)
      hash[workflow_run_id] = permissions
    end

    query = Actions::WorkflowRun.where(
      id: workflow_runs_and_permissions.keys,
      repository: repository
    )

    query.pluck(:id).each do |workflow_run_id|
      permissions = workflow_runs_and_permissions[workflow_run_id]
      permissions.each_pair do |resource, action|
        subject_type = "#{Actions::WorkflowRun::Resources.parent_type}/#{resource}"
        subject = Permissions::Service::PseudoSubject.new(ability_id: workflow_run_id, ability_type: subject_type)

        rows << ::ScopedIntegrationInstallation::Creator.permission_row(
          installation,
          subject,
          action,
          installation.expires_at
        )
      end
    end

    rows
  end

  def permission_rows_for_pull_requests(installation, repository, data)
    rows = []

    return rows unless data.key?("pull_requests")

    # [ { "number" => 1, "permissions" => { "sarifs" => "write" } } ]
    # => { 1 => { "sarifs" => :write } }
    pulls_and_permissions = data["pull_requests"].each_with_object({}) do |pull, hash|
      hash[pull["number"]] = pull["permissions"].transform_values(&:to_sym)
    end

    query = Issue.where(repository: repository, number: pulls_and_permissions.keys).where("issues.pull_request_id IS NOT NULL")

    query.pluck(:pull_request_id, :number).each do |pr_id, number|
      permissions = pulls_and_permissions[number]

      permissions.each_pair do |resource, action|
        subject_type = "#{PullRequest::Resources.parent_type}/#{resource}"
        subject = Permissions::Service::PseudoSubject.new(ability_id: pr_id, ability_type: subject_type)

        rows << ::ScopedIntegrationInstallation::Creator.permission_row(
          installation,
          subject,
          action,
          installation.expires_at
        )
      end
    end

    rows
  end

  # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
  # See https://github.com/github/package-registry-team/issues/7344
  def block_too_many_packages_rows!(packages_rows, flag_name: nil)
    T.bind(self, T.any(
      SiteScopedIntegrationInstallation::Creator,
      SiteScopedIntegrationInstallation::Creators::CodespaceWithOauthAccess,
      SiteScopedIntegrationInstallation::Creators::PrebuildCodespace,
    ))

    packages_count = packages_rows.count
    return if packages_count < target.max_packages_authorizable_per_token

    flipper_enabled = flag_name.present? && target.feature_enabled?(flag_name)

    # Always log something so we can get insights into the limits necessary to protect the database
    log_max_packages_exception(packages_count, flag_name.present?, flipper_enabled)

    # if flag exists and is disabled, we log but don't raise
    return if flag_name.present? && !flipper_enabled

    # raises if flag exists and is enabled
    # raises if no flag is present (behavior is already GA'd)
    raise self.raise_error packages_error_message(target.max_packages_authorizable_per_token)
  end

  # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
  # See https://github.com/github/package-registry-team/issues/7344
  def packages_error_message(max)
    pluralized_packages = "#{max} #{"packages".pluralize(max)}"
    TOO_MANY_PACKAGES_MSG % [pluralized_packages]
  end

  # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
  # See https://github.com/github/package-registry-team/issues/7344
  def log_max_packages_exception(packages_count, flag_present, flipper_enabled)
    T.bind(self, InstallationCreatorTypes)

    log_payload = {
      "gh.request_id" => GitHub.context[:request_id],
      "gh.integration.id" => integration.id,
      "gh.installation.packages_count" => packages_count,
      "gh.installation.target.id" => target.id,
    }
    if flag_present
      log_payload.merge!(
        "gh.installation.max_repos_flipper_enabled" => flipper_enabled
      )
    end
    GitHub.logger.info(
      "Detected an App creating a scoped installation access token exceeding MAX_PACKAGES_ROWS",
      log_payload
    )
  end

  def generate_package_permission_rows_from_repositories(target:, integration:, installation:, repositories:, action:, expires_at: nil)
    T.bind(self, InstallationCreatorTypes)

    requested_permission = action.to_s == "write" ? "administration" : "contents"

    Array(repositories).flat_map do |repository|
      # Get all packages available to this repository and their access_types
      packages = ::PackageRegistry::PackageSubject.get_packages_accessible_by_repo(integration: integration, repository: repository)

      # Add permission rows for each package accessible to the integration for this repo
      packages.flat_map do |package|
        subject = package.resources.public_send(package.access_type) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod

        # Use the access_type assigned to the package and the access being requested to determine how the
        # permissions should be written for the token
        case package.access_type
        when "administration"
          package_action = :write
        when "maintainer"
          package_action = :admin
        else
          package_action = :read
        end
        # If we requested "read", then all written permissions should be for that access type
        if requested_permission == "contents"
          package_action = :read
          subject = package.resources.public_send("contents") # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        end

        Permissions::Service.installation_attributes_hash(actor: installation, subject: subject, action: package_action, expires_at: expires_at)
      end
    end
  end

  def generate_and_validate_permission_rows_for_packages!(integration:, installation:, target:, repositories:, permissions:, expires_at: nil, authorization_details: nil)
    package_action = permissions.dig("packages")

    return [] unless package_action && Apps::Privileged.capable?(:manage_packages_permissions, app: integration)

    attributes = []

    if Apps::Privileged.capable?(:write_legacy_site_scoped_fine_grained_package_permissions, app: integration)
      # Legacy behaviour of writing fine grained package permission rows.
      # Only used by Codespaces.
      # This capability is deprecated and will be removed in the future.
      # All other Global apps like Actions (comming soon to global app)
      # must not use this capability.
      # See https://github.com/github/github/pull/286073

      attributes.concat(
        generate_package_permission_rows_from_repositories(
          target: target,
          integration: integration,
          installation: installation,
          repositories: repositories,
          action: package_action,
          expires_at: expires_at,
        )
      )
    end

    # Packages Permissions Availability TODO: Keep this until we know what to do with Codespaces.
    # See https://github.com/github/package-registry-team/issues/7344
    block_too_many_packages_rows!(attributes, flag_name: :installations_max_packages_grantable)

    if attributes.any? && authorization_details.present?
      resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::PackageRegistry

      attributes.each do |attribute|
        resource = attribute[:subject_type].split("/").last

        @authorization_details.set_asymmetric_for(
          resource_type, resource, attribute[:action], [attribute[:subject_id]]
        )
      end
    end

    opp_row = organization_packages_permission_row(
      target: target,
      installation: installation,
      action: package_action,
      expires_at: expires_at,
    )

    attributes << opp_row

    if authorization_details.present?
      resource_type = ScopedInstallations::AuthorizationDetails::ResourceType::Organization
      name = opp_row[:subject_type].split("/").last

      @authorization_details.set_selection_for(resource_type, ScopedInstallations::AuthorizationDetails::Selection::Subset)
      @authorization_details.set_subject_ids_for(resource_type, [opp_row[:subject_id]]) # This shares the id of the target.

      staa = @authorization_details.subject_types_and_actions_for(resource_type)
      staa[name] = Permission::Action.from(opp_row[:action])

      staa.transform_values!(&:to_sym)

      @authorization_details.set_subject_types_and_actions_for(resource_type, staa)
    end

    attributes
  end

  # Packages Permissions Availability TODO: If possible, we should rename this permission row to better reflect what it is about.
  def organization_packages_permission_row(target:, installation:, action:, expires_at: nil, ar_attributes: false)
    # TODO: Remove this when create we create Target based permissions for packages.
    # Grant the Organization/organization_packages permission for all User type targets.
    subject = IntegrationInstallation::AbilityCollection.new(
      parent: target,
      name: "organization_packages",
      ability_type_prefix: "Organization"
    )

    ::ScopedIntegrationInstallation::Creator.permission_row(installation, subject, action, expires_at, ar_attributes)
  end

  def organization_permissions(permissions)
    org_permissions = Organization::Resources.filter(permissions)

    # The organization_packages permission should only be granted in the
    # context of #grant_packages_permissions and not incidentally.
    #
    # It is theoretically possible for a 1st party app, like Codespaces, to
    # have the organization_packages permission as part of its default
    # version, which can be accidentally granted here if .perform is
    # called with no permissions because we fall back to the app's defaults.
    org_permissions.delete("organization_packages")

    org_permissions
  end

  def permission_rows_to_permissions_by_subject(permission_rows)
    permission_rows.each_with_object({}) do |row, hash|
      parts = row[:subject_type].split("/")
      granted_on_all = !::Permissions::ResourceRegistry
        .individual_type_prefixed_subject_types
        .include?(row[:subject_type])

      resource_type = granted_on_all ? "Repository" : parts.first
      selection_type = granted_on_all ? :all : :subset
      resource_name = parts.last

      subject_key = [resource_type, row[:subject_id], selection_type].join(":")
      hash[subject_key] ||= {}

      hash[subject_key][resource_name] = Permission::Action.from(row[:action]).to_sym
    end
  end
end
