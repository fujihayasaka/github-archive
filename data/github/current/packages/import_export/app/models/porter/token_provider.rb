# typed: true
# frozen_string_literal: true

module Porter
  # Generate an oauth token, if necessary, for API calls to porter.
  #
  # If someone has used porter in their browser, porter will already
  # have an OAuth token and it'll be able to do the work requested via
  # the API. In that case, we don't need to provide a token to porter.
  #
  # If the current user hasn't used porter, porter will need to receive
  # a new token for the user.
  #
  # This class figures out what to do.
  class TokenProvider
    def initialize(application_id: GitHub.porter_app_id)
      @application_id = application_id
    end

    # Public: return nil (if the user already has a token or isn't authorized for workflow scope), or generate a new token.
    def get_token(user)
      return if user.oauth_accesses.find_by_application_id(@application_id)

      application = OauthApplication.find(@application_id)
      oauth_access = user.oauth_accesses.new(
        application_id:   @application_id,
        application_type: "OauthApplication",
        scopes:           application.scopes,
      )
      # Use reset_token to get a plaintext token and force the use of the
      # read/write DB to save the access.
      oauth_access.reset_token
    end
  end
end
