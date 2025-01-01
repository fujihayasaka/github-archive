# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAllowLogin

module GitAuth
  # Note that this class uses ApplicationRecord::Domain in order to
  # avoid relying on ActiveRecord. This is the first step in decoupling
  # gitauth from the github/github, and the lowest level of raw SQL
  # that is currently acceptable in the github/github codebase.
  class SSHKey
    autoload :OauthAuthorization, "git_auth/ssh_key/oauth_authorization"
    autoload :Repository, "git_auth/ssh_key/repository"

    include Scientist

    def self.with_fingerprint_sha256(fingerprint)
      if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get) && fingerprint
        fingerprint = fingerprint << "_#{current_tenant.shortcode}" unless fingerprint.split("_")[1]
      end

      data = ApplicationRecord::Domain::Users.connection.select_all(Arel.sql(<<-SQL, fingerprint: fingerprint)).to_a.first
        SELECT id, `key`, accessed_at, fingerprint_sha256, unverification_reason,
        repository_id, user_id, creator_id, verifier_id, oauth_authorization_id,
        created_by, created_at, verified_at, read_only, bypasses_policy
        FROM public_keys
        WHERE fingerprint_sha256 = :fingerprint
      SQL
      new data if !!data
    end

    attr_reader :id, :key, :accessed_at, :fingerprint_sha256, :unverification_reason,
      :repository_id, :user_id, :creator_id, :verifier_id, :oauth_authorization_id,
      :created_by, :created_at, :verified_at, :read_only, :bypasses_policy
    def initialize(attributes)
      attributes.each do |name, value|
        instance_variable_set("@#{name}", value)
      end
    end

    def fingerprint
      if fingerprint_sha256
        if GitHub.multi_tenant_enterprise?
          "SHA256:#{fingerprint_sha256.split("_")[0]}"
        else
          "SHA256:#{fingerprint_sha256}"
        end
      end
    end

    # Returns [result status Symbol, encoded member or error String]
    def verify(public_key, ssh_required:)
      return [:unknown_key, "Unknown SSH Key"] if key != public_key

      unless ssh_key_user || repository
        return [:unknown_username, "Unknown username"]
      end

      if ssh_key_user && ssh_required
        return [:org_requires_cert, "Organization requires SSH certificate"]
      end

      [:ok, member]
    end

    def type
      user_id ? :user : :repo
    end

    def member
      if user_id
        "user:#{user_id}:#{ssh_key_user.display_login}"
      else
        "repo:#{repository_id}:#{repository.name_with_display_owner}"
      end
    end

    def created_by_unknown?
      created_by == "unknown"
    end

    def read_only?
      # It seems to return different values in different
      # environments.
      [1, "1", true].include?(read_only)
    end

    def bypasses_policy?
      [1, "1", true].include?(bypasses_policy)
    end

    def verified?
      !verified_at.nil?
    end

    # For now, look up the existing Rails user.
    # This gets re-assigned to 'member_object',
    # which gets used in big and complicated ways.
    def user
      @user ||= User.find_by(id: user_id)
    end

    # If we don't need a whole user object, just an id and login,
    # then let's go with the cheaper lookup.
    def ssh_key_user
      @ssh_key_user ||= GitAuth::Login.find(user_id)
    end

    # For now, look up the existing Rails oauth app.
    # This gets used in the OAuthApplicationPolicy,
    # among other things, which I'm not yet ready
    # to decouple.
    def oauth_application
      return @oauth_application if defined?(@oauth_application)
      return nil unless created_by_oauth_application?

      case oauth_authorization.application_type
      when "OauthApplication"
        @oauth_application = OauthApplication.find_by(id: application_id)
      when "Integration"
        @oauth_application = Integration.find_by(id: application_id)
      end
    end

    def verifier
      if @user && @user.id == verifier_id
        GitAuth::Login.new(id: @user.id, login: @user.login, display_login: @user.display_login)
      else
        GitAuth::Login.find(verifier_id)
      end
    end

    def creator
      if @user && @user.id == creator_id
        GitAuth::Login.new(id: @user.id, login: @user.login, display_login: @user.display_login)
      else
        GitAuth::Login.find(creator_id)
      end
    end

    def repository
      @repository ||= GitAuth::SSHKey::Repository.find(repository_id)
    end

    def deploy_key?
      !!repository_id && !!repository
    end

    def created_by_oauth_application?
      oauth_authorization_id && application_id && application_id != OauthApplication::PERSONAL_TOKENS_APPLICATION_ID
    end

    def authorization_active_for_any_orgs?(orgs)
      org_ids = orgs.map(&:id)
      return false if org_ids.empty?
      count = ApplicationRecord::Domain::Users.connection.select_value(Arel.sql(<<-SQL, organization_ids: org_ids, public_key_id: id))
        SELECT COUNT(id)
        FROM organization_credential_authorizations
        WHERE revoked_by_id IS NULL
          AND credential_type = 'PublicKey'
          AND organization_id IN (:organization_ids)
          AND credential_id = :public_key_id
      SQL
      count >= 1
    end

    private

    def oauth_authorization
      @oauth_authorization ||= GitAuth::SSHKey::OauthAuthorization.find(oauth_authorization_id)
    end

    def application_id
      oauth_authorization.application_id
    end
  end
end
