# typed: strict
# frozen_string_literal: true

require "active_support"

module GitHubUI
  # Represents a signed cookie specifies which github-ui SHA to use as an override
  class UIShaCookie
    # The cookie's name.
    NAME = :_ui_sha

    VALIDITY = T.let(1.hour, T.untyped)

    sig { returns(T.nilable(String)) }
    attr_reader :sha
    sig { returns(T.nilable(User)) }
    attr_reader :user
    sig { returns(T.nilable(String)) }
    attr_reader :cookie_value

    sig { params(cookie_value: T.nilable(String)).void }
    def initialize(cookie_value = nil)
      @user = T.let(nil, T.nilable(User))
      @cookie_value = T.let(nil, T.nilable(String))
      @sha = T.let(nil, T.nilable(String))

      verify!(cookie_value)
    end

    # Generates a new, signed, _ui_sha cookie.
    #
    # user - User to use to sign the cookie
    # sha - The Github UI SHA
    #
    # Returns a GitHubUI::UIShaCookie if the passed user is an employee.
    # Otherwise returns nil.
    sig { params(user: User, sha: String).returns(T.nilable(GitHubUI::UIShaCookie)) }
    def self.generate(user:, sha:)
      cookie = self.new
      cookie.sign!(user, sha)
      cookie if cookie.valid?
    end

    # Reads a valid signed cookie out of a cookie jar.
    sig { params(jar: T.untyped).returns(T.nilable(GitHubUI::UIShaCookie)) }
    def self.read(jar)
      ui_sha_cookie = self.new(jar[NAME] || jar[NAME.to_s])
      ui_sha_cookie if ui_sha_cookie.valid?
    end

    # Deletes the cookie from a cookie jar.
    sig { params(jar: T.untyped).void }
    def self.delete!(jar)
      jar.delete(NAME, domain: cookie_domain)
    end

    # Determine the domain used for setting cookies.
    # According to new cookie standards in RFC 6265, there is now no need to add a leading '.' to a cookie domain for the cookie to apply to a subdomain.
    # i.e. a cookie domain of '.github.com' and 'github.com' mean the same thing.
    sig { returns(String) }
    def self.cookie_domain
      return GitHub.host_name if GitHub.enterprise?

      # Note: GitHub.host_name_with_tenant can also include the port, but this isn't supported for the domain attribute in the cookie.
      # For example, the sha might be something like `github.localhost:80` when starting the server in a codespace.
      return GitHub.host_name_with_tenant.split(":").first if Rails.env.development?

      GitHub.host_name_with_tenant
    end

    # Saves the cookie to a cookie jar.
    sig { params(jar: T.untyped).void }
    def save!(jar)
      return unless valid?

      jar[NAME] = {
        domain: self.class.cookie_domain,
        value: @cookie_value,
      }
    end

    sig { params(user: User).returns(T::Boolean) }
    def self.allowed_user?(user)
      if GitHub.require_employee_for_site_admin?
        user.try(:employee?)
      else
        user.try(:site_admin?)
      end
    end

    sig { returns(T::Boolean) }
    def valid?
      @sha.present? && @user.present? && @cookie_value.present?
    end

    sig { params(sha: String).returns(String) }
    def token_scope(sha)
      "StaffOnlyUISha:#{sha}"
    end


    sig { params(user: User, sha: String).void }
    def sign!(user, sha)
      return unless self.class.allowed_user?(user)

      token = user.signed_auth_token(
        scope: token_scope(sha),
        expires: VALIDITY.from_now,
      )

      @user = user
      @sha = sha
      @cookie_value = "#{sha}--#{token}"
    end

    sig { params(cookie_value: T.nilable(String)).returns(T::Boolean) }
    def verify!(cookie_value)
      return false unless cookie_value
      return false if GitHub.multi_tenant_enterprise? && !GitHub::CurrentTenant.stafftools_tenant?

      sha, unverified_token = cookie_value.split("--", 2)

      # We use the staff only cookie in a number of middleware
      # checks where the database selection might not have happened
      # yet. It's safe to always use the replicas here for getting
      # a user.
      ActiveRecord::Base.connected_to(role: :reading) do
        token = GitHub::Authentication::SignedAuthToken.verify(
          token: unverified_token,
          scope: token_scope(T.must(sha)),
        )

        if token.valid? && self.class.allowed_user?(token.user)
          @user = token.user
          @sha = sha
          @cookie_value = cookie_value
          return true
        else
          return false
        end
      end
    end
  end
end
