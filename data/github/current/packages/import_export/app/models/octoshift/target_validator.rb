# typed: true
# frozen_string_literal: true

module Octoshift
  class TargetValidator
    NEEDED_PAT_SCOPES = %w(repo workflow).freeze

    def initialize(source:, owner:, user:, github_pat:)
      @source = source
      @owner = owner
      @user = user
      @token = token_for_pat_string(github_pat)
    end

    def owner_matches?
      source.owner_id == owner.id
    end

    def user_can_import_repo?
      AuthorizationPolicy.can_import_repo?(user: user, owner: owner)
    end

    def pat_valid?
      !!token
    end

    def pat_can_import_repo?
      Octoshift::AuthorizationPolicy.can_import_repo?(user: token.user, owner: owner)
    end

    def owner_has_allowlisted_ips?
      Octoshift::ValidationHelper.allows_octoshift_ips?(owner)
    end

    def missing_pat_scopes
      return NEEDED_PAT_SCOPES unless token

      NEEDED_PAT_SCOPES - token.scopes
    end

    def pat_needs_sso?
      return false if skip_sso_validation?

      !token || !Organization::CredentialAuthorization.where(
        organization_id: owner.id,
        credential_id: token.id,
        credential_type: "OauthAccess"
      ).exists?
    end

    def repository_exists?(name)
      owner.repositories.exists?(name: name)
    end

    def valid_visibility?(visibility)
      return true if visibility.nil?

      Repository::VISIBILITIES.include?(visibility)
    end

    private

    attr_reader :source, :owner, :user, :token

    def token_for_pat_string(pat)
      OauthAccess.with_active_token(pat)
    end

    def skip_sso_validation?
      !(owner.saml_sso_enabled? || business_sso_enabled?) ||
        GitHub.flipper[:sso_same_business_cred_authz_private_repos].enabled?(user) ||
        GitHub.flipper[:octoshift_disable_target_sso_validation].enabled?(owner)
    end

    def business_sso_enabled?
      return false unless owner.business

      owner.sso_enabled_on_business?
    end
  end
end
