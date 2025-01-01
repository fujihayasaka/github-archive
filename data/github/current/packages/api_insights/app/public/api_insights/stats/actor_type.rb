# typed: strict
# frozen_string_literal: true

module ApiInsights::Stats
  class ActorType < T::Enum
    enums do
      OauthApp = new("oauth_app")
      ClassicPat = new("classic_pat")
      FineGrainedPat = new("fine_grained_pat")
      GithubAppUserToServer = new("github_app_user_to_server")
      Installation = new("installation")
    end
  end
end
