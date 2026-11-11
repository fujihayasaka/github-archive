# typed: false
# frozen_string_literal: true

module GitHub::Authentication::Feed
  # Public: Create a SignedAuthToken for accessing an Atom feed.
  #
  # user - The User to create the token for.
  # path - The URL path of the feed the token is for.
  #
  # Returns a String token.
  def self.token(user, path)
    user.signed_auth_token(
      scope: scope(path),
      expires: 50.years.from_now,
    )
  end

  # Public: The scope to use when creating or verifying a SignedAuthToken for an
  # Atom feed.
  #
  # path - The URL path of the feed the token is for.
  #
  # Returns a String scope.
  def self.scope(path)
    "Atom:#{path}"
  end

  def authentication_methods
    if user = login_from_user_session
      nil # Don't need to instrument this.
    elsif user = login_from_signed_auth_token(feed_token_scope)
      GitHub.dogstats.increment "auth.feeds", tags: ["action:authentication_methods", "type:signed_auth_token"]
    elsif token_request_format? && user = login_from_authorization_header_auth
      return nil if user.using_oauth_application?
      type = if user.using_oauth?
        "personal_access_token"
      else
        "password"
      end
      GitHub.dogstats.increment "auth.feeds", tags: ["action:authentication_methods", "type:#{type}"]
    end

    user
  end

  def feed_token_scope
    GitHub::Authentication::Feed.scope request.path
  end

  def feed_actions
    raise NotImplementedError
  end

  def token_request_format?
    feed_actions.include?(action_name) && request.format && request.format.atom?
  end

  def stateless_request?
    token_request_format? || super
  end
end
