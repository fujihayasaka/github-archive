# typed: true
# frozen_string_literal: true

class Api::AccessControl < Egress::AccessControl

  def self.resource_must_belong_to_repo(access)
    access.ensure_context :repo, :resource do |repo, resource|
      repo && repo.id == resource.try(:repository_id)
    end
  end

  # List direct child scopes for a given scope.
  #
  # TODO: Move this to Egress::Scope.children and return full ivars, not just name.
  #
  # scope - Egress::Scope or String scope name
  #
  # Returns an array of Egress::Scope objects.
  def self.child_scopes(scope)
    scope = case scope
    when Egress::Scope
      scope
    when String
      scopes[scope]
    end

    return [] unless scope

    scopes.slice(*scope.send(:children).map(&:name)).values
  end

  scope "repo",
    description: "full control of private repositories",
    visibility: :grantable

  scope "repo:status",
    description: "access commit status",
    parent: "repo",
    visibility: :grantable

  scope "repo_deployment",
    description: "access deployment status",
    parent: "repo",
    visibility: :grantable,
    no_sudo: true

  scope "public_repo",
    description: "access public repositories",
    parent: "repo",
    visibility: GitHub.multi_tenant_enterprise? ? :hidden : :grantable

  scope "repo:invite",
    description: "access repository invitations",
    parent: "repo",
    visibility: :grantable

  scope "delete_repo",
    description: "delete repositories",
    visibility: :grantable

  scope "user",
    description: "update ALL user data",
    visibility: :grantable

  scope "read:user",
    description: "read ALL user profile data",
    parent: "user",
    visibility: :grantable,
    no_sudo: true

  scope "user:email",
    description: "access user email addresses (read-only)",
    parent: "user",
    visibility: :grantable,
    no_sudo: true

  scope "user:follow",
    description: "follow and unfollow users",
    parent: "user",
    visibility: :grantable,
    no_sudo: true

  scope "admin:org",
    description: "full control of orgs and teams, read and write org projects",
    visibility: :grantable

  scope "write:org",
    description: "read and write org and team membership, read and write org projects",
    parent: "admin:org",
    visibility: :grantable,
    no_sudo: true

  scope "read:org",
    description: "read org and team membership, read org projects",
    parent: "write:org",
    visibility: :grantable,
    no_sudo: true

  scope "manage_runners:org",
    description: "manage org runners and runner groups",
    parent: "admin:org",
    visibility: :grantable

  scope "write:network_configurations",
    description: "write org hosted compute network configurations",
    visibility: GitHub.enterprise? ? :hidden : :grantable

  scope "read:network_configurations",
    description: "read org hosted compute network configurations",
    parent: "write:network_configurations",
    visibility: GitHub.enterprise? ? :hidden : :grantable

  scope "write:discussion",
    description: "read and write team discussions",
    visibility: :grantable,
    no_sudo: true

  scope "read:discussion",
    description: "read team discussions",
    parent: "write:discussion",
    visibility: :grantable,
    no_sudo: true

  scope "admin:public_key",
    description: "full control of user public keys",
    visibility: :grantable

  scope "write:public_key",
    description: "write user public keys",
    parent: "admin:public_key",
    visibility: :grantable

  scope "read:public_key",
    description: "read user public keys",
    parent: "write:public_key",
    visibility: :grantable,
    no_sudo: true

  scope "admin:gpg_key",
    description: "full control of public user GPG keys",
    visibility: :grantable

  scope "write:gpg_key",
    description: "write public user GPG keys",
    parent: "admin:gpg_key",
    visibility: :grantable

  scope "read:gpg_key",
    description: "read public user GPG keys",
    parent: "write:gpg_key",
    visibility: :grantable,
    no_sudo: true

  scope "admin:ssh_signing_key",
    description: "full control of public user SSH signing keys",
    visibility: :grantable

  scope "write:ssh_signing_key",
    description: "write public user SSH signing keys",
    parent: "admin:ssh_signing_key",
    visibility: :grantable

  scope "read:ssh_signing_key",
    description: "read public user SSH signing keys",
    parent: "write:ssh_signing_key",
    visibility: :grantable,
    no_sudo: true

  scope "admin:repo_hook",
    description: "full control of repository hooks",
    visibility: :grantable

  scope "write:repo_hook",
    description: "write repository hooks",
    parent: "admin:repo_hook",
    visibility: :grantable

  scope "read:repo_hook",
    description: "read repository hooks",
    parent: "write:repo_hook",
    visibility: :grantable,
    no_sudo: true

  scope "write:packages",
    description: "upload packages to GitHub Package Registry",
    visibility: PackageRegistryHelper.show_packages? ? :grantable : :hidden,
    no_sudo: true

  scope "read:packages",
    description: "download packages from GitHub Package Registry",
    parent: "write:packages",
    visibility: PackageRegistryHelper.show_packages? ? :grantable : :hidden,
    no_sudo: true

  scope "delete:packages",
    description: "delete packages from GitHub Package Registry",
    visibility: PackageRegistryHelper.show_packages? ? :grantable : :hidden,
    no_sudo: true

  scope "admin:org_hook",
    description: "full control of organization hooks",
    visibility: :grantable

  scope "admin:pre_receive_hook",
        description: "control enforcement of pre-receive hooks for an organization or repository",
        visibility: :grantable

  scope "gist",
    description: "create gists",
    no_sudo: true,
    visibility: :grantable

  scope "notifications",
    description: "access notifications",
    no_sudo: true,
    visibility: :grantable

  scope "site_admin",
    description: "access site administrator API endpoints",
    visibility: GitHub.enterprise? ? :grantable : :public

  scope "devtools",
    description: "access devtools API endpoints",
    parent: "site_admin",
    visibility: GitHub.enterprise? ? :hidden : :grantable

  scope "biztools",
    description: "access biztools API endpoints",
    parent: "site_admin",
    visibility: GitHub.enterprise? ? :hidden : :grantable

  scope "admin:enterprise",
    description: "full control of enterprises",
    visibility: :grantable

  scope "manage_runners:enterprise",
    description: "manage enterprise runners and runner groups",
    parent: "admin:enterprise",
    visibility: :grantable

  scope "manage_billing:enterprise",
    description: "read and write enterprise billing data",
    parent: "admin:enterprise",
    visibility: :grantable

  scope "read:enterprise",
    description: "read enterprise profile data",
    parent: "manage_billing:enterprise",
    visibility: :grantable

  scope "codespace",
    description: "full control of codespaces",
    visibility: :grantable

  scope "codespace:secrets",
    description: "ability to create, read, update, and delete codespace secrets",
    parent: "codespace",
    visibility: :grantable

  scope "copilot",
    description: "full control of GitHub Copilot settings and seat assignments",
    visibility: GitHub.enterprise? ? :hidden : :grantable

  scope "manage_billing:copilot",
    description: "view and edit Copilot Business seat assignments",
    parent: "copilot",
    visibility: GitHub.enterprise? ? :hidden : :grantable

  scope "project",
    description: "full control of projects",
    visibility: :grantable

  scope "read:project",
    description: "read access of projects",
    parent: "project",
    visibility: :grantable

  scope "audit_log",
    description: "full control of audit log",
    visibility: :grantable

  scope "read:audit_log",
    description: "read access of audit log",
    parent: "audit_log",
    visibility: :grantable

  # TODO: Can we rename and kill these?
  scope "user:assets",
    description: "upload and read user assets"
  scope "user:assets:read",
    description: "read uploaded user assets",
    parent: "user:assets"

  scope "workflow",
    description: "update GitHub Action workflows",
    visibility: :grantable

  scope "security_events",
    description: "read and write security events",
    parent: "repo",
    visibility: :grantable

  # Hide scopes from Personal Access Token screens temporarily
  # until they're ready to :ship:.
  #
  # name - String name of scope
  #
  # Returns a Boolean
  def self.grantable?(name)
    return false if self.scopes[name]&.visibility == :hidden

    preview_scopes = %w(write:network_configurations read:network_configurations)

    preview_scopes.exclude?(name)
  end

  # Internal: is this resource a PullRequest
  # or a sub-resource of a PullRequest, e.g. an IssueComment
  def self.related_to_a_pull_request?(resource)
    case resource
    when PullRequest
      true
    when Issue
      resource.pull_request?
    when IssueComment, IssueEvent
      resource.issue&.pull_request?
    end
  end

  def self.issue_must_be_readable(access)
    access.ensure_context :user, :resource do |user, resource|
      issue = if resource.is_a?(Issue) || resource.is_a?(Discussion)
        resource
      elsif resource.respond_to?(:issue)
        resource.issue
      end

      issue && issue.readable_by?(user)
    end
  end

  def self.public_repository?(owner)
    owner.is_a?(Repository) && owner.public?
  end

  # Internal: Does the given actor have restricted access to modify public
  # resources?
  #
  # TODO: Duplicated from issues_access_dependency. Refactor.
  #
  # Applies only to GitHub Apps that must have fine-grained permission on a
  # public resource. E.g. GitHub Actions.
  #
  # actor - User/Bot that is capable of having granular permissions.
  #
  # Returns a Boolean.
  def self.restricted_modification_of_public_resources?(actor)
    return false unless actor && actor.can_have_granular_permissions? && actor.respond_to?(:integration)
    Apps::Internal.capable?(
      :restricted_modification_of_public_resources,
      app: actor.integration,
    )
  end

  # Internal: does the user's permission match the resource requested?
  #
  # Restrictions only apply to users with granular permissions, i.e. installations.
  # An installation can only access a PR, or PR sub-resource,
  # if permissions are only on PRs. An installation can only access an issue,
  # or issue sub-resource, if permissions are only on issues.
  def self.issue_must_match_permission(context, permission)
    user, resource, repo = extract(context, :user, :resource, :repo)
    actor = user.try(:installation) || user

    return true if user && !actor.can_have_granular_permissions?

    subject = if related_to_a_pull_request?(resource)
      repo.resources.pull_requests
    elsif resource.is_a?(Discussion)
      repo.resources.discussions
    else
      repo.resources.issues
    end

    if permission == :write
      subject.writable_by?(user)
    else
      subject.readable_by?(user)
    end
  end

  def self.discussion_must_be_readable(access)
    access.ensure_context :user, :resource do |user, discussion|
      discussion && discussion.readable_by?(user)
    end
  end

  # Array of String scope names: Scopes that do not allow privileged access to
  # organization-owned resources (i.e., these scopes do not provide the ability
  # to view private org resources or mutate public org resources.)
  SCOPES_WITHOUT_PRIVILEGED_ORGANIZATION_ACCESS = %w(
    read:user
    user:email
    user:follow
    admin:public_key
    write:public_key
    read:public_key
    admin:gpg_key
    write:gpg_key
    read:gpg_key
    gist
  ).freeze

  # Array of String scope names: Scopes that provide some kind of access to
  # private repositories. These scopes provide at least enough access to make a
  # request that will reveal the *existence* of a private repository.
  SCOPES_WITH_PRIVATE_REPOSITORY_ACCESS = %w(
    delete_repo
    repo
    repo_deployment
    repo:status
    admin:repo_hook
    write:repo_hook
    read:repo_hook
    security_events
  ).freeze
end

# Load the rules from config
Dir["#{Rails.root}/config/access_control/*.rb"].each do |file|
  load file
end
