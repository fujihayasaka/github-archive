# typed: true
# frozen_string_literal: true

module GitAuth
  class PushHandler
    class NoActorError < StandardError
    end

    # SAFELY DEPLOYING CHANGES:
    #
    # If making changes here and in #commit_refs_pack_ctx
    # on different hosts, with different deploys. So changes may need to be
    # staged over two deploys.
    #
    # Returns an actor, or nil.
    def actor_from_ctx(ctx_json)
      return if ctx_json.nil?
      ctx = GitHub::JSON.parse(ctx_json)
      auth_type = ctx.key?("auth_type") && ctx["auth_type"].to_sym

      if auth_type == :bot && ctx.key?("installation_id") && ctx.key?("installation_type")
        # Fetching the Bot through the IntegrationInstallation or
        # ScopedIntegrationInstallation hydrates it with the repository
        # installation which is the abilities delegate.
        # Fetching the Bot through the SiteScopedIntegrationInstallation hydrates
        # it with the global installation which is the abilities delegate.
        installation =
          case ctx["installation_type"]
          when "IntegrationInstallation"
            IntegrationInstallation.find(ctx["installation_id"].to_i)
          when "ScopedIntegrationInstallation"
            ScopedIntegrationInstallation.find(ctx["installation_id"].to_i)
          when "SiteScopedIntegrationInstallation"
            SiteScopedIntegrationInstallation.find(ctx["installation_id"].to_i)
          end
        T.must(installation).bot
      elsif ctx.key?("user_id")
        user = User.find(ctx["user_id"].to_i)
        if ctx.key?("oauth_access_id")
          # Re-attach the oauth access that was used to authenticate so that we
          # can check the scopes used later in RefUpdatesPolicy.
          user.oauth_access = OauthAccess.find(ctx["oauth_access_id"].to_i)
        elsif ctx.key?("user_programmatic_access_id")
          user.programmatic_access = ProgrammaticAccess.find(ctx["user_programmatic_access_id"].to_i)
        end
        user
      elsif ctx.key?("pubkey_id")
        PublicKey.find(ctx["pubkey_id"].to_i)
      elsif ctx.key?("slumlord") && ctx["slumlord"] == "true"
        :slumlord
      else
        Failbot.push({
          "gh.gitauth.type": ctx["auth_type"],
          "gh.installation.type": ctx["installation_type"],
          "gh.installation.id": ctx["installation_id"],
          "gh.user.id": ctx["user_id"],
          "gh.oauth.access.id": ctx["oauth_access_id"],
          "gh.user_programmatic_access.id": ctx["user_programmatic_access_id"],
          "gh.public_key.id": ctx["pubkey_id"],
          "gh.gitauth.svnbridge_mode": ctx["slumlord"]
        })
        raise NoActorError, "context missing installation_id, installation_type, user_id and pubkey_id"
      end
    rescue ActiveRecord::RecordNotFound
      Failbot.push({
        "gh.gitauth.type": ctx["auth_type"],
        "gh.installation.type": ctx["installation_type"],
        "gh.installation.id": ctx["installation_id"],
        "gh.user.id": ctx["user_id"],
        "gh.oauth.access.id": ctx["oauth_access_id"],
        "gh.user_programmatic_access.id": ctx["user_programmatic_access_id"],
        "gh.public_key.id": ctx["pubkey_id"],
        "gh.gitauth.svnbridge_mode": ctx["slumlord"]
      })
      raise NoActorError, "record was deleted before lookup could complete"
    end
  end
end
