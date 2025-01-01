# typed: strict
# frozen_string_literal: true

module GitHub
  # Represents a signed cookie that marks the user as a GitHub employee, and
  # also specifies whether to use the Lab environment or not.
  class PerformanceProfilingCookie
    extend T::Helpers

    NAME = :perf_profiling
    VALIDITY = T.let(5.minutes, ActiveSupport::Duration)
    VALUE = T.let("true", T.nilable(String))

    sig { returns(T.nilable(User)) }
    attr_accessor :user

    sig { returns(T.nilable(String)) }
    attr_accessor :value

    sig { returns(T.nilable(String)) }
    attr_accessor :cookie_value

    sig { params(user: User).returns(T.nilable(GitHub::PerformanceProfilingCookie)) }
    def self.generate(user)
      cookie = self.new
      cookie.sign!(user, VALUE)
      cookie if cookie.send(:valid?)
    end

    sig { params(jar: T.any(GitHub::AllowlistedCookieJar, T::Hash[T.untyped, T.untyped])).returns(T.nilable(GitHub::PerformanceProfilingCookie)) }
    def self.read(jar)
      cookie = self.new(jar[NAME] || jar[NAME.to_s])
      cookie if cookie.send(:valid?)
    end

    sig { params(jar: T.any(GitHub::AllowlistedCookieJar, T::Hash[T.untyped, T.untyped])).void }
    def self.delete!(jar)
      T.unsafe(jar).delete(NAME, domain: cookie_domain)
    end

    sig { params(cookie_value: T.nilable(String)).void }
    def initialize(cookie_value = nil)
      verify!(cookie_value)
    end

    sig { returns(T::Boolean) }
    def valid?
      value.present? && user.present? && cookie_value.present?
    end

    sig { params(jar: T.any(GitHub::AllowlistedCookieJar, T::Hash[T.untyped, T.untyped])).void }
    def save!(jar)
      return unless valid?

      jar[NAME] = {
        domain: self.class.cookie_domain,
        value: @cookie_value,
      }
    end

    sig { params(user: GitHub::VexiActor).returns(T::Boolean) }
    def self.allowed_user?(user)
      user.feature_flag_enabled?(:performance_profiling_allowed, default: false)
    end

    sig { returns(String) }
    def self.cookie_domain
      return GitHub.host_name if GitHub.enterprise?

      # Note: GitHub.host_name_with_tenant can also include the port, but this isn't supported for the domain attribute in the cookie.
      # For example, the sha might be something like `github.localhost:80` when starting the server in a codespace.
      return GitHub.host_name_with_tenant.split(":").first if Rails.env.development?

      GitHub.host_name_with_tenant
    end

    sig { params(user: User, value: T.nilable(String)).void }
    def sign!(user, value)
      return unless self.class.allowed_user?(user)

      token = user.signed_auth_token(
        scope: token_scope(value),
        expires: VALIDITY.from_now,
      )

      self.user         = user
      self.value        = value
      self.cookie_value = "#{value}--#{token}"
    end

    private

    sig { params(value: T.nilable(String)).returns(String) }
    def token_scope(value)
      "PerformanceProfiling:#{value}"
    end

    sig { params(cookie_value: T.nilable(String)).returns(T::Boolean) }
    def verify!(cookie_value)
      return false unless cookie_value

      value, unverified_token = cookie_value.split("--", 2)

      ActiveRecord::Base.connected_to(role: :reading) do
        token = GitHub::Authentication::SignedAuthToken.verify(
          token: unverified_token,
          scope: token_scope(value),
        )

        if token.valid? && self.class.allowed_user?(token.user)
          self.user         = token.user
          self.value        = value
          self.cookie_value = cookie_value
          return true
        else
          return false
        end
      end
    end
  end
end
