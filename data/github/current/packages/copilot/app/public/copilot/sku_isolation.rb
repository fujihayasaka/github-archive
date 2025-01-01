# typed: strict
# frozen_string_literal: true

module Copilot
  class SKUIsolation
    extend T::Sig

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

    sig { returns(Copilot::User) }
    attr_reader :copilot_user

    sig { returns(T.nilable(::Business)) }
    attr_reader :current_tenant

    sig { params(copilot_user: Copilot::User, current_tenant: T.nilable(::Business)).void }
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
      return BUSINESS if has_copilot_standalone_business?
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
      copilot_user.copilot_plan
    end

    sig { returns(T::Boolean) }
    memoize def has_copilot_standalone_business?
      copilot_user.has_copilot_standalone_business?
    end

    sig { params(key: Symbol).returns(T::Boolean) }
    def feature_enabled?(key)
      feature = GitHub.flipper[key]

      return true if feature.enabled?(copilot_user.user_object)

      copilot_user.copilot_organizations.each do |copilot_organization|
        return true if feature.enabled?(copilot_organization.organization_object)

        copilot_business = copilot_organization.copilot_business
        next unless copilot_business

        return true if feature.enabled?(copilot_business.business_object)
      end

      false
    end
  end
end
