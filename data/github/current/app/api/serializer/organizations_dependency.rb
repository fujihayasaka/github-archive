# typed: true
# frozen_string_literal: true

module Api::Serializer::OrganizationsDependency
  extend T::Helpers
  include Api::Serializer::AvatarsDependency
  include Api::Serializer::UserDependency
  include Api::Serializer::RepositoriesDependency
  include Api::Serializer::CustomPropertiesDependency

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON.
  #
  # org     - Organization instance
  # options - Hash
  #           :full    - Boolean specifying we want the extended output.
  #           :private - Boolean specifying we want the private output.
  #
  # Returns a Hash if the org exists, or nil.
  def organization_hash(org, options = {})
    return nil if !org
    options = Api::SerializerOptions.from(options)
    org_api_path = "/orgs/#{org.login_for_api(use: options[:serialize_login])}"
    hash = {
      login: org.login_for_api(use: options[:serialize_login]),
      id: org.id,
      node_id: global_id_for(org, options),
      url: url(org_api_path, options),
      repos_url: url("#{org_api_path}/repos", options),
      events_url: url("#{org_api_path}/events", options),
      hooks_url: url("#{org_api_path}/hooks", options),
      issues_url: url("#{org_api_path}/issues", options),
      members_url: url("#{org_api_path}/members{/member}", options),
      public_members_url: url("#{org_api_path}/public_members{/member}", options),
      avatar_url: avatar(org),
      description: org.description,
    }

    include_details =  options[:full] || options[:private] || options[:owner_private]

    if include_details && (profile = org.profile)
      hash.update \
        name: profile.name,
        company: profile.company,
        blog: profile.blog,
        location: profile.location,
        email: profile.email,
        twitter_username: profile.twitter_username
    end

    if include_details
      hash[:is_verified] = org.is_verified?
    end

    if include_details
      hash.update \
        has_organization_projects: org.organization_projects_enabled?,
        has_repository_projects: org.repository_projects_enabled?,
        public_repos: org.repository_counts.public_repositories,
        public_gists: org.repository_counts.public_gists,
        followers: org.followers_count(viewer: nil), # TODO: Remove this in v3
        following: org.following_count(viewer: nil), # TODO: Remove this in v3
        html_url: org.permalink,
        created_at: time(org.created_at),
        updated_at: time(org.updated_at),
        archived_at: time(org.archived_at),
        type: org[:type]
    end

    if options[:private] || options[:owner_private]
      hash.update \
        total_private_repos: org.repository_counts.private_repositories,
        owned_private_repos: org.repository_counts.owned_private_repositories,
        private_gists: nil,
        disk_usage: nil,
        collaborators: nil,
        billing_email: nil,
        default_repository_permission: nil,
        members_can_create_repositories: org.members_can_create_repositories?,
        two_factor_requirement_enabled: nil,
        members_allowed_repository_creation_type: org.members_allowed_repository_creation_type,
        members_can_create_public_repositories: org.members_can_create_public_repositories?,
        members_can_create_private_repositories: org.members_can_create_private_repositories?,
        members_can_create_internal_repositories: org.members_can_create_internal_repositories?,
        members_can_create_pages: org.members_can_create_pages?,
        members_can_fork_private_repositories: org.allow_private_repository_forking?,
        web_commit_signoff_required: org.dco_signoff_enabled?

      if GitHub.flipper[:private_pages_org_toggle].enabled?(org)
        hash[:members_can_create_public_pages] = org.members_can_create_public_pages?
        hash[:members_can_create_private_pages] = org.members_can_create_private_pages?
      end
    end

    if options[:private] || options[:owner_private] || options[:plan]
      plan = {
        name: org.plan.display_name,
        space: org.plan.space / 1.kilobyte,
        private_repos: org.plan.org_repos(feature_flag: :plans_munich)
      }

      if options[:current_user]
        plan.update \
          filled_seats: org.filled_seats,
          seats: org.seats
      end

      hash.update \
        plan: plan
    end

    if options[:owner_private]
      hash.update \
        private_gists: org.repository_counts.private_gists,
        disk_usage: org.disk_usage,
        collaborators: org.collaborators_count,
        billing_email: org.billing_email,
        default_repository_permission: org.default_repository_permission_name,
        two_factor_requirement_enabled: org.two_factor_requirement_enabled?
    end

    if options[:show_security_feature_auto_enablement_settings]
      push_protection_features = SecretScanning::Features::Org::PushProtection.new(org)

      unless options.changeset_active?(:remove_organization_security_product_enablement)
        hash.update(
          advanced_security_enabled_for_new_repositories: org.advanced_security_enabled_on_new_repos?,
          dependabot_alerts_enabled_for_new_repositories: org.security_alerts_enabled_for_new_repos?,
          dependabot_security_updates_enabled_for_new_repositories: org.vulnerability_updates_enabled_for_new_repos?,
          dependency_graph_enabled_for_new_repositories: org.dependency_graph_enabled_for_new_repos?,
          secret_scanning_enabled_for_new_repositories: SecretScanning::Features::Org::TokenScanning.new(org).secret_scanning_enabled_for_new_repos?,
          secret_scanning_push_protection_enabled_for_new_repositories: push_protection_features.enabled_for_new_repos?,
        )
      end

      unless options.changeset_active?(:remove_secret_scanning_custom_link_enablement_field)
        hash[:secret_scanning_push_protection_custom_link_enabled] = push_protection_features.custom_message_enabled?
      end

      hash[:secret_scanning_push_protection_custom_link] = push_protection_features.custom_message_active? ? org.get_push_protection_custom_message : nil

      unless GitHub.single_or_multi_tenant_enterprise? || options.changeset_active?(:remove_organization_security_product_enablement)
        hash[:secret_scanning_validity_checks_enabled] = SecretScanning::Features::Org::ValidityChecks.new(org).enabled?
      end
    end

    hash
  end

  def invitation_hash(invitation, options = {})
    return nil if !invitation
    options = Api::SerializerOptions.from(options)

    {}.tap do |opts|
      opts[:id]         = invitation.id
      opts[:node_id]    = global_id_for(invitation, options)
      opts[:login]      = invitation.email.nil? ? invitation.invitee.login_for_api(use: options[:serialize_login]) : nil
      opts[:email]      = invitation.email.nil? ? fetch_field(invitation.invitee.profile, :email) : invitation.email
      opts[:role]       = invitation.role.to_s
      opts[:created_at] = invitation.created_at
      opts[:failed_at]  = invitation.failed_at
      opts[:failed_reason] = invitation.failed_reason_description
      opts[:inviter]    = user_hash(invitation.inviter, content_options(options))
      opts[:team_count] = invitation.teams.count
      opts[:invitation_teams_url] = url("/organizations/#{invitation.organization_id}/invitations/#{invitation.id}/teams", options)
      opts[:invitation_source] = invitation.invitation_source
    end
  end

  # Creates a Hash to be serialized to JSON.
  #
  # team    - Team instance
  # options - Hash
  #           :full    - Boolean specifying we want the extended output.
  #
  # Returns a Hash if the team exists, or nil.
  def team_hash(team, options = {})
    return unless team
    options = Api::SerializerOptions.from(options)
    hash = team_simple_hash(team, options)

    hash[:ldap_dn] = team.ldap_dn if team.ldap_mapped?

    if options[:full]
      hash.update \
        created_at: time(team.created_at),
        updated_at: time(team.updated_at),
        members_count: team.members_scope_count(membership: :all),
        repos_count: team.repositories_scope_count(affiliation: :all),
        organization: organization_hash(team.organization, options.merge(full: true))
    end

    if options[:exclude_parent]
      hash[:parent] = nil
    else
      hash[:parent] = team_simple_hash(team.parent_team, options)
    end

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # data - a hash of property values
  # options    - Hash
  #
  # Returns a Hash of repository identification with an array of
  # property names and values
  def repo_property_effective_values_hash(data, options = {})
    return unless data

    repository = data[:repository]
    property_values = data[:property_values]

    {
      repository_id: repository.id,
      repository_name: repository.name,
      repository_full_name: repository.name_with_display_owner,
      properties: property_values.map do |property_name, value|
        {
          property_name: property_name,
          value: value
        }
      end
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # property_values_hash - Hash of property names and values
  # options   - Hash
  #
  # Returns a Hash of property names and values
  def custom_property_values_hash(property_values_hash, options = {})
    return unless property_values_hash

    property_values_hash.map do |property_name, value|
      {
        property_name: property_name,
        value: value
      }
    end
  end


  # Internal: a method to build a hash that matches the team-simple schema. The
  # idea here is that you could compose more complex team representations using
  # this method to give you a base to work from.
  #
  # Returns Hash
  private def team_simple_hash(team, options = {})
    return unless team

    team_api_path = "/organizations/#{team.organization_id}/team/#{team.id}"
    hash = {
      name: team.name,
      id: team.id,
      node_id: global_id_for(team, options),
      slug: team.to_param,
      description: team.description,
      privacy: team.privacy.to_s,
      notification_setting: team.notification_setting.to_s,
      url: url(team_api_path),
      html_url: team.permalink,
      members_url: url("#{team_api_path}/members{/member}"),
      repositories_url: url("#{team_api_path}/repos"),
    }

    if repo = options[:repo]

      team_permission = team.async_most_capable_action_or_role_for(repo, include_custom_roles: true, role_priority: true).sync
      team_permission = Team::ABILITIES_TO_PERMISSIONS[team_permission] if Team::ABILITIES_TO_PERMISSIONS.key?(team_permission)
      hash[:permission] = team_permission
      hash[:permissions] = permissions_hash(repo, actor: team)
    else
      hash[:permission] = team.permission.blank? ? "pull" : team.permission
    end

    hash
  end

  SimpleTeamFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Team {
      createdAt @include(if: $includeFullTeamDetails)
      updatedAt @include(if: $includeFullTeamDetails)
      name
      databaseId
      id
      slug
      description
      privacy
      notificationSetting
      permission
      ldapDn
      resourcePath
      parentTeam {
        name
        databaseId
        id
        slug
        description
        privacy
        notificationSetting
        permission
        resourcePath
        membersResourcePath
        repositoriesResourcePath
        organization {
          databaseId
        }
      }
      organization {
        databaseId
      }
      immediate_members: members(membership: IMMEDIATE) {
        totalCount
      }
      all_members: members(membership: ALL) @include(if: $includeFullTeamDetails){
        totalCount
      }
      immediate_repositories: repositories(affiliation: IMMEDIATE) {
        totalCount
      }
      all_repositories: repositories @include(if: $includeFullTeamDetails){
        totalCount
      }
      resourcePath
      membersResourcePath
      repositoriesResourcePath
    }
  GRAPHQL

  TeamFragment = Api::App::PlatformClient.parse <<-'GRAPHQL'
    fragment on Team {
      ...Api::Serializer::OrganizationsDependency::SimpleTeamFragment
      organization {
        hasProfile
        hasOrganizationProjectsEnabled
        hasRepositoryProjectsEnabled
        isVerified
        avatarUrl
        description
        login
        name
        company
        location
        blog: websiteUrl
        twitterUsername
        email
        databaseId
        id
        createdAt
        updatedAt
        archivedAt
        resourcePath
        repositories(privacy: PUBLIC) {
          totalCount
        }
        gists(privacy: PUBLIC) {
          totalCount
        }
      }
    }
  GRAPHQL

  def graphql_team_hash(team, options = {})
    if options[:full]
      team_with_organization = TeamFragment.new(team)
      team = SimpleTeamFragment.new(team_with_organization)
    else
      team = SimpleTeamFragment.new(team)
    end

    hash = build_team_hash(team)
    options = Api::SerializerOptions.from(options)

    if team.parent_team.present?
      hash[:parent] = build_team_hash(team.parent_team)
    else
      hash[:parent] = nil
    end

    if options[:full]
      # We can't use team.ldap_mapped? here as this is a GraphQL TeamFragment
      # not a Team object
      hash[:ldap_dn] = team.ldap_dn if GitHub.ldap_sync_enabled? && team.ldap_dn?

      hash.update \
        created_at: time(team.created_at),
        updated_at: time(team.updated_at),
        members_count: team.all_members.total_count,
        repos_count: team.all_repositories.total_count,
        organization: build_organization_hash(team_with_organization.organization, full: true)
    end

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # org     - Organization instance
  # options - Hash
  #           :user - User instance to check membership of.
  #           :full = Whether or not to include the Organization.
  #
  # Returns a Hash if the organization and user exist, or nil.
  def org_membership_hash(org, options = {})
    options = Api::SerializerOptions.from(options)
    user = options[:user]
    wants_org = options[:full].nil? ? true : options[:full]
    wants_org_permissions = options.accepts_param?(:permissions)

    return nil unless org
    return nil unless user

    role = org_membership_type(org, user)

    can_create_repository = false
    if wants_org_permissions
      invitation = org.pending_invitation_for(user)
      can_create_repository = invitation.nil? && org.can_create_repository?(user, role: role)
    end

    hash = {
      url: url("/orgs/#{org.login_for_api(use: options[:serialize_login])}/memberships/#{user.login_for_api(use: options[:serialize_login])}"),
      state: org.membership_state_of(user).to_s,
      role: role.to_s,
      organization_url: url("/orgs/#{org.login_for_api(use: options[:serialize_login])}"),
      user: user_hash(user, content_options(options)),
    }

    if wants_org
      hash.update(organization: organization_hash(org, options))
    end

    if wants_org_permissions
      hash.update \
        permissions: {
          can_create_repository: can_create_repository,
        }
    end

    hash
  end

  # Creates a Hash to be serialized to JSON.
  #
  # data - Hash
  #        :permissions - array of permission strings
  #        :organization - the organization
  #        :user - the user
  # options - Hash
  # Returns a Hash with permissions and membership the user has for the org.
  def org_member_permissions_hash(data, options = {})
    {
      permissions: data[:permissions],
      membership: org_membership_type(data[:organization], data[:user])
    }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # data - Hash
  #        :permissions - array of permission strings
  # options - Hash
  # Returns a Hash with permissions the team has over the org.
  def org_team_permissions_hash(data, options = {})
    { permissions: data[:permissions] }
  end

  # Creates a Hash to be serialized to JSON.
  #
  # data    - Hash
  #           :team - Team instance
  #           :user - User instance
  # options - Hash (unused)
  #
  # Returns a Hash if the team and user exist and there's a membership between
  # them, or nil.
  def team_membership_hash(data, options = {})
    team = data[:team]
    user = data[:user]

    return nil unless team.present?
    return nil unless user.present?

    role = if team.maintainer?(user) || team.owner?(user)
      "maintainer"
    elsif Team.member_of?(team.id, user.id, immediate_only: false)
      "member"
    elsif invitation = team.pending_invitation_for(user)
      # If the user is invited to the org, check if they're invited to this
      # team.
      if team_invitation = invitation.team_invitation_for(team)
        # If they are, use their role from that invitation
        team_invitation.role.to_s
      end
    end

    {
      state: team.membership_state_of(user, immediate_only: false).to_s,
      role: role || "unaffiliated",
      url: url("/organizations/#{team.organization_id}/team/#{team.id}/memberships/#{user.login_for_api(use: options[:serialize_login])}"),
    }
  end

  private def build_team_hash(team)
    team_api_path = "/organizations/#{team.organization.database_id}/team/#{team.database_id}"
    {
      name: team.name,
      id: team.database_id,
      node_id: team.id,
      slug: team.slug,
      description: team.description,
      privacy: team.privacy.downcase == "visible" ? "closed" : team.privacy.downcase,
      notification_setting: team.notification_setting.downcase,
      url: url(team_api_path),
      html_url: html_url(team.resource_path),
      members_url: url("#{team_api_path}/members{/member}"),
      repositories_url: url("#{team_api_path}/repos"),
      permission: team.permission.downcase,
    }
  end

  private def build_organization_hash(org, options = {})
    org_api_path = "/orgs#{org.resource_path}"
    # Hash is used specifically for GraphQL and login in GraphQL already return display login
    hash = {
      login: org.login, # rubocop:disable GitHub/DoNotAllowLogin
      id: org.database_id,
      node_id: org.id,
      url: url(org_api_path),
      repos_url: url("#{org_api_path}/repos"),
      events_url: url("#{org_api_path}/events"),
      hooks_url: url("#{org_api_path}/hooks"),
      issues_url: url("#{org_api_path}/issues"),
      members_url: url("#{org_api_path}/members{/member}"),
      public_members_url: url("#{org_api_path}/public_members{/member}"),
      avatar_url: org.avatar_url.to_s,
      description: org.description,
    }

    include_details = options[:full]
    if include_details && org.has_profile?
      hash.update \
        name: org.name,
        company: org.company,
        blog: org.blog.to_s,
        location: org.location,
        email: org.email,
        twitter_username: org.twitter_username
    end

    if include_details
      hash[:is_verified] = org.is_verified?
    end

    if include_details
      hash.update \
        has_organization_projects: org.has_organization_projects_enabled?,
        has_repository_projects: org.has_repository_projects_enabled?,
        public_repos: org.repositories.total_count,
        public_gists: org.gists.total_count,
        followers: 0,
        following: 0,
        html_url: "#{GitHub.url}#{org.resource_path}",
        created_at: time(org.created_at),
        updated_at: time(org.updated_at),
        archived_at: time(org.archived_at),
        type: "Organization"
    end

    hash
  end

  private def org_membership_type(org, user)
    role = if !org.member?(user) && invitation = org.pending_invitation_for(user)
      invitation.role
    else
      org.role_of(user).type
    end

    # Sanitize the role
    case role.to_s
    when "direct_member"
      role = :member
    when "outside_collaborator"
      role = :unaffiliated
    end

    role
  end
end
