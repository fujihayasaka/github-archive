# typed: true
# frozen_string_literal: true

module Media
  module Token
    # Returns the User (or subclass) given the token object.  If the token is
    # invalid or not for a user, returns nil.
    def self.user_for_token(token)
      return nil unless token.valid?
      return nil unless user = token.user

      if user.is_a?(Bot)
        installation = if token.installation_type == "ScopedIntegrationInstallation"
          ScopedIntegrationInstallation.includes(:integration).find_by(id: token.installation_id)
        elsif token.installation_type == "SiteScopedIntegrationInstallation"
          SiteScopedIntegrationInstallation.includes(:integration).find_by(id: token.installation_id)
        else
          IntegrationInstallation.includes(:integration).find_by(id: token.installation_id)
        end

        user = installation.bot if installation&.bot
      end
      user
    end

    # Returns the Repository given the token object.  If the token is invalid or
    # the member is not a Repository (e.g., the token is for a user), returns
    # nil.
    def self.repo_for_token(token)
      return nil unless token.valid?
      return nil unless token.data.is_a?(Hash)
      return nil unless repo_id = Media.repo_id_from_member(token.data["member"])
      repo = Repository.find_by(id: repo_id)
      return nil unless repo == token.repo
      repo
    end

    # Returns the PublicKey representing the deploy key for which the token was
    # issued given the token object.  If the token is invalid or the token is
    # not for a deploy key (e.g., the token is for a user), returns nil.
    def self.deploy_key_for_token(token)
      return nil unless token.valid?
      return nil unless token.respond_to?(:public_key)
      token.public_key
    end

    # Returns a token for the given user, scope, repository, and expiration
    # time.  This function does not validate that the user has permissions to be
    # granted this access; the caller is responsible for that.
    def self.gitauth_token_for_user(user, scope, repo, expires)
      data = if user.is_a?(Bot) && user.installation.present?
        {
          "installation_id" => user.installation.id,
          "installation_type" => user.installation.class.to_s,
        }
      else
        {}
      end

      GitHub::Authentication::GitAuth::SignedAuthToken.generate(
        repo: repo,
        scope: scope,
        expires: expires,
        data: {
          "member" => "user:#{user.id}:#{user.login}",
          "proto" => "ssh",
        }.merge(data)
      )
    end

    # Returns a token for the given deploy key, scope, repository, and
    # expiration time.  This function does not validate that the deploy key has
    # permissions to be granted this access; the caller is responsible for that.
    def self.gitauth_token_for_deploy_key(key, scope, repo, expires)
      GitHub::Authentication::GitAuth::SignedAuthToken.generate(
        repo: repo,
        scope: scope,
        expires: expires,
        data: {
          "member" => "repo:#{repo.id}:#{repo.nwo}",
          "proto" => "ssh",
          "deploy_key" => key.id
        }
      )
    end

    # Returns a token for the given actor, scope, repository, and expiration
    # time.  The actor may be a User (or derived class) or a PublicKey (which
    # should be a deploy key).  This function does not validate that the actor
    # has permissions to be granted this access; the caller is responsible for
    # that.
    def self.gitauth_token_for_actor(actor, scope, repo, expires)
      if actor.is_a?(PublicKey) || actor.is_a?(GitAuth::SSHKey)
        gitauth_token_for_deploy_key(actor, scope, repo, expires)
      else
        gitauth_token_for_user(actor, scope, repo, expires)
      end
    end
  end
end
