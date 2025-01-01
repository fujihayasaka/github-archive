# typed: strict
# frozen_string_literal: true

module AccountSwitcher
  class Helper
    extend T::Sig
    include GitHub::Memoizer
    include FeatureFlagHelper

    # Maximum number of accounts which can be present in the `saved_user_sessions` cookie
    SAVED_ACCOUNTS_LIMIT = 10

    sig { params(user: T.nilable(User), saved_user_session_hash: T.nilable(T::Hash[String, String])).void }
    def initialize(user, saved_user_session_hash)
      @user = user
      @saved_user_session_hash = saved_user_session_hash
    end

    # determines whether the AccountSwitcher feature is available
    sig { params(additional_user_check: T.nilable(User)).returns(T::Boolean) }
    def enabled?(additional_user_check: nil)
      return true unless @saved_user_session_hash.nil?
      return true if !!@user
      return true if additional_user_check
      false
    end

    # determines if the user if the user can add accounts in the current
    # browser session.
    sig { returns(T::Boolean) }
    def can_add_account?
      !!(@user && enabled? && !at_account_maximum?)
    end

    # returns the StashedAccounts derived from the saved user session data,
    # including both valid and invalid sessions, but excluding the session for
    # the current_user.
    sig { returns(StashedAccounts) }
    memoize def stashed_accounts
      stashed_accounts = StashedAccounts.new(valid: [], invalid: [])
      return stashed_accounts unless enabled?
      return stashed_accounts if @saved_user_session_hash.nil?
      @saved_user_session_hash.reduce(stashed_accounts) do |accounts, (user_id, session_key)|
        # ignore keys that match the user (if a user exists) or that do not belong to a user at all
        if !(@user && @user.id == user_id) && user = User.find_by(id: user_id)
          if result = UserSession.authenticate(session_key)
            user_session, user_session_key = result
            if user_session.user_id == user_id
              accounts.valid << StashedAccount.new(
                user: user_session.user,
                user_session_key: user_session_key,
                user_session: user_session,
                valid: true,
              )
            else
              # saved_user_session cookie is malformed. in lieu of a bug, the user has manually modified the cookie,
              # so we should ignore this entry.
              GitHub.dogstats.increment("account_switcher.saved_session_mismatch")
            end
          else
            # we need to include the (invalid) user_session_key here for correlation in SessionsController#remove_inactive
            accounts.invalid << StashedAccount.new(user: user, user_session_key: session_key)
          end
        end

        accounts
      end
    end

    # determines if the provided user_id belongs to any authenticated stashed accounts available
    sig { params(user_id: T.nilable(Integer)).returns(T::Boolean) }
    def account_already_exists?(user_id)
      return false unless user_id
      return false unless enabled?
      stashed_accounts.valid.any? { |stashed_account| stashed_account.user.id == user_id }
    end

    # determines if the provided display_login belongs to any invalid stashed accounts
    sig { params(display_login: T.nilable(String)).returns(T::Boolean) }
    def invalid_account_already_exists?(display_login)
      return false unless display_login
      return false unless enabled?
      stashed_accounts.invalid.any? { |stashed_account| stashed_account.user.display_login == display_login }
    end

    # check to determine if the user already has the maximum number of accounts in the account switcher
    sig { returns(T::Boolean) }
    def at_account_maximum?
      return false unless enabled?
      # stashed accounts exclude the current user account, so include it if the user is logged in
      saved_accounts = stashed_accounts.all.size
      saved_accounts += 1 if @user
      saved_accounts >= SAVED_ACCOUNTS_LIMIT
    end
  end
end
