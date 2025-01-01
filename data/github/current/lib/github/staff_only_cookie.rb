# typed: true
# frozen_string_literal: true

require "active_support"

module GitHub
  # Represents a signed cookie that marks the user as a GitHub employee, and
  # also specifies whether to use the Lab environment or not.
  class StaffOnlyCookie
    # The cookie's name.
    NAME = :staffonly

    VALIDITY = 1.hour

    VALUES   = {
      lab: "true".freeze,
      employee: "yes".freeze,
    }

    attr_reader :user, :cookie_value

    def initialize(cookie_value = nil)
      verify!(cookie_value)
    end

    # Generates a new, signed, staffonly cookie.
    #
    # user - User to use to sign the cookie
    # for_lab - Boolean specifying whether to use the Lab environment.
    #
    # Returns a GitHub::StaffOnlyCookie if the passed user is an employee.
    # Otherwise returns nil.
    def self.generate(user:, for_lab:)
      cookie = self.new
      cookie.send(:sign!, user, for_lab ? VALUES[:lab] : VALUES[:employee])
      cookie if cookie.send(:valid?)
    end

    # Reads a valid signed cookie out of a cookie jar.
    #
    # Returns a GitHub::StaffOnlyCookie if a valid and verified cookie is found
    # in the cookie jar. Otherwise, returns nil.
    def self.read(jar)
      employee_only_cookie = self.new(jar[NAME] || jar[NAME.to_s])
      return employee_only_cookie if employee_only_cookie.send(:valid?)
    end

    # Deletes the cookie from a cookie jar.
    #
    # jar - The ApplicationController::CookieJar to delete from.
    def self.delete!(jar)
      jar.delete(NAME, domain: cookie_domain)
    end

    # Determine the domain used for setting cookies.
    # According to new cookie standards in RFC 6265, there is now no need to add a leading '.' to a cookie domain for the cookie to apply to a subdomain.
    # i.e. a cookie domain of '.github.com' and 'github.com' mean the same thing.
    def self.cookie_domain
      return GitHub.host_name if GitHub.enterprise?

      # Note: GitHub.host_name_with_tenant can also include the port, but this isn't supported for the domain attribute in the cookie.
      # For example, the value might be something like `github.localhost:80` when starting the server in a codespace.
      return GitHub.host_name_with_tenant.split(":").first if Rails.env.development?

      GitHub.host_name_with_tenant
    end

    def for_lab?
      @value == VALUES[:lab]
    end

    # Saves the cookie to a cookie jar.
    #
    # jar    - The ApplicationController::CookieJar to save to.
    # secure - Boolean specifying whether the cookie is only transmitted via
    #          HTTPS.
    def save!(jar)
      return unless valid?

      jar[NAME] = {
        domain: self.class.cookie_domain,
        value: @cookie_value,
      }
    end

    def self.allowed_user?(user)
      if GitHub.require_employee_for_site_admin?
        user.try(:employee?)
      else
        user.try(:site_admin?)
      end
    end

    private

    def valid?
      defined?(@value) && defined?(@user) && defined?(@cookie_value)
    end

    def token_scope(value)
      "StaffOnly:#{value}"
    end

    def sign!(user, value)
      return unless self.class.allowed_user?(user)

      token = user.signed_auth_token(
        scope: token_scope(value),
        expires: VALIDITY.from_now,
      )

      @user         = user
      @value        = value
      @cookie_value = "#{value}--#{token}"
    end

    def verify!(cookie_value)
      return false unless cookie_value
      return false if GitHub.multi_tenant_enterprise? && !GitHub::CurrentTenant.stafftools_tenant?

      value, unverified_token = cookie_value.split("--", 2)

      # We use the staff only cookie in a number of middleware
      # checks where the database selection might not have happened
      # yet. It's safe to always use the replicas here for getting
      # a user.
      ActiveRecord::Base.connected_to(role: :reading) do
        token = GitHub::Authentication::SignedAuthToken.verify(
          token: unverified_token,
          scope: token_scope(value),
        )

        if token.valid? && self.class.allowed_user?(token.user)
          @user         = token.user
          @value        = value
          @cookie_value = cookie_value
          return true
        else
          return false
        end
      end
    end
  end
end
