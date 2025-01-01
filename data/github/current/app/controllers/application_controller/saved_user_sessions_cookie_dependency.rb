# typed: true
# frozen_string_literal: true

# Saved user sessions cookie controller concern
# Used for CRUD operations of the saved user sessions cookie for the AccountSwitcher
module ApplicationController::SavedUserSessionsCookieDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  included do
    T.cast(self, AbstractController::Helpers::ClassMethods).helper_method :account_switcher_helper
  end

  SAVED_USER_SESSION_COOKIE_NAME = :saved_user_sessions
  # since the cookie is touched every time an account is added or removed, this expiration will be
  # frequently refreshed similar to `user_session`.
  SAVED_USER_SESSION_LIFETIME_IN_DAYS = 90

  sig { returns(AccountSwitcher::Helper) }
  memoize def account_switcher_helper
    AccountSwitcher::Helper.new(current_user, saved_user_session_hash)
  end

  # updates the saved_user_sessions cookie to include the provided. if no sessions
  # are provided, it deletes the cookie instead.
  sig { params(keys_hash: T::Hash[String, String]).void }
  def update_saved_user_session_cookie(keys_hash)
    existing_hash = saved_user_session_hash || {}
    updated_hash = existing_hash.merge(keys_hash)
    if updated_hash.empty?
      GitHub.dogstats.increment("account_switcher.cookie_dependency", tags: [
        "result:deleted",
        "action:update_saved_user_session_cookie"
      ])
      delete_cookie
    else
      GitHub.dogstats.increment("account_switcher.cookie_dependency", tags: [
        "result:update",
        "action:update_saved_user_session_cookie"
      ])
      set_cookie(value: encode_saved_user_session_cookie(**updated_hash))
    end
  end

  # deletes the provided session keys from the saved_user_sessions cookie
  sig { void }
  def delete_saved_user_sessions_cookie
    cookies.delete(SAVED_USER_SESSION_COOKIE_NAME)
  end

  # deletes the provided session keys from the saved_user_sessions cookie
  sig { params(keys: String).void }
  def delete_saved_user_session_keys(*keys)
    existing_hash = saved_user_session_hash
    return if existing_hash.nil?
    updated_hash = existing_hash.reject do |_, key|
      keys.include?(key)
    end
    GitHub.dogstats.increment("account_switcher.cookie_dependency", tags: [
      "result:update",
      "action:delete_saved_user_session_keys"
    ])
    set_cookie(value: encode_saved_user_session_cookie(updated_hash))
  end

  private

  # returns a hash of user ID to user session key based on the
  # encoded contents of the saved_user_session cookie
  # if the cookie does not exist, explicity returns nil
  sig { returns(T.nilable(T::Hash[String, String])) }
  def saved_user_session_hash
    return nil unless saved_user_sessions_cookie_exists?

    value = get_cookie.presence || ""
    value.split("|").map do |account_key|
      id, secret = account_key.split(":")
      [id.to_i, secret]
    end.to_h
  end

  # encodes a hash of user ID to user session key for storage in the
  # saved_user_sessions_cookie
  sig { params(keys_hash: T::Hash[String, String]).returns(String) }
  def encode_saved_user_session_cookie(keys_hash)
    keys_hash.map { |user_id, key| "#{user_id}:#{key}" }.join("|")
  end

  # returns true if the cookie exists
  # returns false if no such cookie is present
  sig { returns(T::Boolean) }
  def saved_user_sessions_cookie_exists?
    get_cookie.present?
  end

  sig { returns(T.nilable(String)) }
  def get_cookie
    cookies[SAVED_USER_SESSION_COOKIE_NAME]
  end

  sig { params(value: String).void }
  def set_cookie(value:)
    cookies[SAVED_USER_SESSION_COOKIE_NAME] = {
      value: value,
      expires: SAVED_USER_SESSION_LIFETIME_IN_DAYS.days.from_now,
    }
  end

  sig { void }
  def delete_cookie
    cookies.delete(SAVED_USER_SESSION_COOKIE_NAME)
  end
end
