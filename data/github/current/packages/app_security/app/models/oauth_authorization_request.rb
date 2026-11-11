# typed: true
# frozen_string_literal: true

# Public: An OauthAuthorizationRequest represents a request from an application
# asking a user to grant an OauthAccess to the application.
#
# TODO: Currently, this class represents only a tiny fraction of the domain
# concepts associated with an OAuth authorization request. Much of the domain
# logic resides in OauthController. Over time, we hope to move the relevant
# domain concepts out of OauthController and into this class, thus freeing the
# controller to function solely as a traffic cop.
class OauthAuthorizationRequest
  attr_reader :application, :scopes, :user

  # Public: Initialize an OauthAuthorizationRequest.
  #
  # attributes - The Hash used for initialization (default: {}):
  #              :application - The OauthApplication requesting authorization.
  #              :scopes      - The Array of String scope names being requested.
  #              :user        - The User from whom the application is requesting
  #                             authorization.
  def initialize(attributes = {})
    @application = attributes[:application]
    @scopes = attributes[:scopes]
    @user = attributes[:user]
  end

  # Public: If this authorization request were approved by the user, would it
  # give the application a dangerous level of access to @github's repositories
  # and other resources?
  #
  # Returns a Boolean.
  def dangerous_to_github?
    return if GitHub.enterprise?

    user.employee? && scopes_disallowed_by_github.any?
  end

  # Public: Some applications are partially trusted by @github. @github
  # employees can authorize those applications for specific (allowed) scopes
  # defined in APPLICATIONS_PARTIALLY_TRUSTED_BY_GITHUB. If this application is
  # partially trusted by @github, and it is asking for scopes that @github
  # employees are not allowed to grant to this application, return those
  # disallowed scopes.
  #
  # Returns an Array of String scope names.
  def scopes_disallowed_by_github
    policy = APPLICATIONS_PARTIALLY_TRUSTED_BY_GITHUB[application.key]
    return [] if policy.nil?

    allowed_scopes = policy[:scopes]
    scopes.reject { |scope| allowed_scopes.include?(scope) }
  end

  # Internal: Hash defining applications partially trusted @github. @github's
  # organization application policy allows these applications to access @github
  # resources, but we only want GitHubbers to grant certain (allowed) scopes to
  # these apps.
  #
  # In this Hash, each key is the String client ID for a production application
  # on github.com, and the value is a Hash containing an Array of allowed String
  # scope names.
  #
  # See https://github.com/github/github/pull/35831 for background.
  APPLICATIONS_PARTIALLY_TRUSTED_BY_GITHUB = {
    "f244293c729d5066cf27" => {
      name: "Travis CI",
      scopes: %w(
        public_repo
        read:org
        repo_deployment
        repo:status
        user
        user:email
        write:repo_hook
      ),
    },
    "3fe1696ae02990ae1249" => {
      name: "AppVeyor",
      scopes: %w(
        read:org
        user:email
      ),
    },
    "01881570529737c25f97" => {
      name: "AppVeyor CI",
      scopes: %w(
        admin:repo_hook
        read:org
        repo:status
      ),
    },
    "0eb0331510337bb496f2" => {
      name: "GitHub Blocks",
      scopes: %w(
        repo
      ),
    },
  }.freeze
  private_constant :APPLICATIONS_PARTIALLY_TRUSTED_BY_GITHUB
end
