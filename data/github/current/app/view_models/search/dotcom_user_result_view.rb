# typed: true
# frozen_string_literal: true

module Search
  class DotcomUserResultView < UserResultView

    attr_reader :created_at, :profile_bio, :email, :avatar_url, :user_link

    # Create a new DotcomUserResultView from a `user` document hash returned from
    # the dotcom api.
    #
    # dotcom_hash - Document Hash returned by dotcom api
    #
    def initialize(dotcom_hash)
      user = dotcom_hash["_model"]
      @display_login = user&.display_login

      @id        = dotcom_hash["id"]
      @login     = dotcom_hash["login"]
      @name      = dotcom_hash["name"]
      @email = dotcom_hash["email"]
      @location  = dotcom_hash["location"]
      @repos     = dotcom_hash["public_repos"]
      @followers = dotcom_hash["followers"]
      @created_at  = Time.parse(dotcom_hash["created_at"])
      @profile_bio = dotcom_hash["bio"]
      @avatar_url = dotcom_hash["avatar_url"]
      @user_link = dotcom_hash["html_url"]
      @highlights  = Search::DotcomHighlights.highlights(dotcom_hash["text_matches"])
    end
  end  # UserResultView
end  # Search
