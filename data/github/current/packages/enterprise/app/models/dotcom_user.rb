# typed: true
# frozen_string_literal: true

# Information for github.com user who has linked their account
# to a local user on this Enterprise install

class DotcomUser < ApplicationRecord::Domain::Users

  belongs_to :user

  before_destroy :remove_user_contributions
  before_destroy :revoke_oauth_token

  def github_profile_url
    github_url = "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_host_name}"
    URI.join(github_url, EscapeUtils.escape_uri_component(display_login)).to_s
  end

  def display_login
    User.to_display_login(login)
  end

  def remove_user_contributions
    return unless token
    GitHub::Connect.remove_user_contributions(token)
  rescue GitHub::Connect::ApiError => e
    # Removal failures are usually due to dotcom-terminated connections,
    # we'll only care (and re-raise) if we can't actually talk to dotcom
    raise e if e.class.in? [
      GitHub::Connect::ServiceUnavailableError,
      GitHub::Connect::TimeoutError,
    ]
  end

  def revoke_oauth_token
    return unless token
    connection = ::DotcomConnection.new
    authenticator = connection.authenticator
    app_info = authenticator.request_oauth_application
    authenticator.revoke_oauth_token(token, app_info, connection.client_secret)
  end

  def self.for(user)
    find_by(user_id: user.id) || new(user_id: user.id)
  end

  def self.user_connected?(user)
    self.for(user).token.present?
  end

  def self.update_user_last_contributions_sync(user)
    self.for(user).touch(:last_contributions_sync)
  end
end
