# typed: strict
# frozen_string_literal: true

module Copilot
  class SKUIsolation

    include GitHub::Memoizer

    Endpoints = T.type_alias do
      {
        "api" => String,
        "origin-tracker" => String,
        "proxy" => String,
        "telemetry" => String,
      }
    end

    ALL_PLANS = T.let([
      INDIVIDUAL = T.let("individual".freeze, String),
      BUSINESS = T.let("business".freeze, String),
      ENTERPRISE = T.let("enterprise".freeze, String),
    ].freeze, T::Array[String])

    # Creates a new SKUIsolation object for the given user. This can be used
    # from controllers/etc where only `current_user` is available.
    sig { params(user: T.nilable(::User), public_user_enabled: T::Boolean).returns(Copilot::SKUIsolation) }
    def self.for_user(user, public_user_enabled: false)
      user ||= ::User.new

      # Use cached Copilot::Public::User when feature flag is enabled
      if user.feature_flag_enabled?(:copilot_sku_isolation_use_public_user_perf, default: false) || public_user_enabled
        if user.persisted?
          new(Copilot::Public::User.new(user), GitHub::CurrentTenant.get)
        else
          # Copilot::Public::User requires a persisted user when it tries to create a copilot configuration record,
          # so just return a SKUIsolation with no user.
          # will default to individual plan and non-enforced endpoints.
          new(nil, GitHub::CurrentTenant.get)
        end
      else
        new(Copilot::User.new(user), GitHub::CurrentTenant.get)
      end
    end

    sig { returns(T.nilable(T.any(Copilot::User, Copilot::Public::User))) }
    attr_reader :copilot_user

    sig { returns(T.nilable(::Business)) }
    attr_reader :current_tenant

    sig { params(copilot_user: T.nilable(T.any(Copilot::User, Copilot::Public::User)), current_tenant: T.nilable(::Business)).void }
    def initialize(copilot_user, current_tenant)
      @copilot_user = copilot_user
      @current_tenant = current_tenant
    end

    # Whether the Copilot SKU-specific hosts/endpoints should be returned for
    # the current user.
    sig { returns(T::Boolean) }
    memoize def discovery_enabled?
      feature_enabled?(:copilot_sku_isolation_discovery)
    end

    # Controls enforcement of SKU Isolation for Copilot API.
    sig { returns(T::Boolean) }
    memoize def enforce_api?
      feature_enabled?(:copilot_sku_isolation_enforce_api)
    end

    # Controls enforcement of SKU Isolation for Copilot Proxy.
    sig { returns(T::Boolean) }
    memoize def enforce_proxy?
      feature_enabled?(:copilot_sku_isolation_enforce_proxy)
    end

    # Returns the current plan for the user. If the Copilot::User returns an
    # unknown plan, it will default to "individual".
    sig { returns(String) }
    memoize def plan
      return BUSINESS if has_copilot_business? || has_copilot_standalone_business?

      return copilot_user_plan if ALL_PLANS.include?(copilot_user_plan)

      INDIVIDUAL
    end

    # Returns a hash of all service endpoints.
    sig { returns(Endpoints) }
    memoize def endpoints
      {
        "api" => api.endpoint,
        "origin-tracker" => origin_tracker.endpoint,
        "proxy" => proxy.endpoint,
        "telemetry" => telemetry.endpoint,
      }
    end

    # Copilot API
    sig { returns(Service) }
    memoize def api
      Service.new do
        case
        when override = GitHub.copilot_api_override_url
          override
        when tenant = current_tenant
          "copilot-api.#{tenant.slug}.ghe.com"
        when discovery_enabled?
          "api.#{plan}.githubcopilot.com"
        else
          "api.githubcopilot.com"
        end
      end
    end

    # Snippy
    sig { returns(Service) }
    memoize def origin_tracker
      Service.new do
        case
        when discovery_enabled?
          "origin-tracker.#{plan}.githubcopilot.com"
        else
          "origin-tracker.githubusercontent.com"
        end
      end
    end

    # Copilot Proxy
    sig { returns(Service) }
    memoize def proxy
      Service.new do
        case
        when discovery_enabled?
          "proxy.#{plan}.githubcopilot.com"
        else
          "copilot-proxy.githubusercontent.com"
        end
      end
    end

    # Copilot Telemetry Service
    sig { returns(Service) }
    memoize def telemetry
      Service.new do
        case
        when tenant = current_tenant
          "copilot-telemetry-service.#{tenant.slug}.ghe.com"
        when discovery_enabled?
          "telemetry.#{plan}.githubcopilot.com"
        else
          "copilot-telemetry-service.githubusercontent.com"
        end
      end
    end

    private

    sig { returns(String) }
    memoize def copilot_user_plan
      copilot_user&.copilot_plan || INDIVIDUAL
    end

    sig { returns(T::Boolean) }
    memoize def has_copilot_business?
      return false unless T.unsafe(copilot_user).is_a?(Copilot::Public::User)

      public_user = T.cast(copilot_user, Copilot::Public::User)
      # has_cb_access? returns true if folks belong to an enterprise plan so we should check this first as it takes preceedence
      return false if public_user.has_ce_access?

      # Then check has_cb_access? for business plan access
      public_user.has_cb_access?
    end

    sig { returns(T::Boolean) }
    memoize def has_copilot_standalone_business?
      return false unless T.unsafe(copilot_user).is_a?(Copilot::User)

      legacy_user = T.cast(copilot_user, Copilot::User)
      legacy_user.has_copilot_standalone_business?
    end

    sig { returns(T.nilable(::User)) }
    memoize def user
      copilot_user&.user_object
    end

    sig { params(key: Symbol).returns(T::Boolean) }
    def feature_enabled?(key)
      return true if FeatureFlag.vexi.enabled?(key, user, default: false)
      return false if user.nil?

      T.must(user).organizations.each do |organization|
        return true if organization.feature_flag_enabled_or_raise?(key) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      T.must(user).businesses.each do |business|
        return true if business.feature_flag_enabled_or_raise?(key) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
      end

      false
    end
  end
end
