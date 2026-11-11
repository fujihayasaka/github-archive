# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  # This is a wrapper around the ::User class.
  # It adds in methods related to Copilot
  class User < SimpleDelegator

    include GitHub::Memoizer
    include Copilot::Metrics
    include Copilot::Abuse
    include ::Billing::Abuse::Copilot::AuthAndCapture
    include Copilot::Users::Abuse
    include Copilot::Users::Access
    include Copilot::Users::ApiNotifications
    include Copilot::Users::Enterprise
    include Copilot::Users::InstrumentationDetails
    include Copilot::Users::Settings
    include Copilot::Users::Subscription
    include Copilot::Users::TechnicalPreview
    include Copilot::Users::CodespacesDemo
    include Copilot::Users::ContentExclusion
    include Copilot::Users::Mailable
    include Copilot::Users::ModelAccess
    include Copilot::Users::Policies
    include Copilot::Users::PremiumInteractions
    include Copilot::Users::CodingGuidelines
    include Copilot::Users::CodeReview
    include Copilot::Users::Usage
    include Targeting::Targetable

    include Vexi::Actor

    delegate \
      :disabled?,
      :async_customer,
      :feature_flag_enabled?,
      :feature_flag_enabled_or_raise?,
      :is_enterprise_managed?,
      :organizations,
      to: :user_object

    sig do params(
        user: ::User,
        integration_id: String,
        session: T.nilable(UserSession),
        real_ip: T.nilable(String),
        token: T.nilable(::Copilot::Token),
        request_id: T.nilable(String)
      ).returns(Copilot::User::CopilotApi)
    end
    def self.copilot_api(user:, integration_id:, session: nil, real_ip: nil, token: nil, request_id: nil) # rubocop:disable Style/OptionalArguments
      unless request_id
        if defined?(::GitHub) && ::GitHub.respond_to?(:context)
          request_id = ::GitHub.context[:request_id]
        end
      end

      Copilot::User::CopilotApi.new(
        user,
        integration_id: integration_id,
        session: session,
        real_ip: real_ip,
        token: token,
        api_version: api_version_for(user),
        request_id: request_id,
      )
    end

    sig { params(user: ::User).returns(String) }
    def self.api_version_for(user)
      if user.feature_flag_enabled?(:copilot_api_version_20250501, default: true)
        CopilotAPI::VERSION_2025_05_01
      else
        CopilotAPI::VERSION_DEFAULT
      end
    end

    sig { params(user: ::User).void }
    def initialize(user)
      super
    end

    sig { returns(Class) }
    def sorbet_class
      ::User
    end

    sig { returns(Integer) }
    def id
      T.must(user_object.id)
    end

    sig { override.returns(::User) }
    def user_object
      __getobj__
    end

    sig { override.returns(::User) }
    def configurable_object
      user_object
    end

    sig { override.returns(Copilot::User) }
    def copilot_user_object
      self
    end

    sig { override.returns(Copilot::TelemetrySnapshot) }
    memoize def telemetry_snapshot
      Copilot::TelemetrySnapshot.new(self)
    end

    sig { override.returns(T.nilable(String)) }
    memoize def telemetry_snapshot_id
      telemetry_snapshot.telemetry_snapshot_id
    end

    sig { override.returns(Copilot::Authorizer) }
    memoize def copilot_authorizer_object
      Copilot::Authorizer.new(copilot_user_object)
    end

    sig { override.returns(Copilot::Authorizer) }
    memoize def copilot_authorizer_object_no_snippy
      Copilot::Authorizer.new(copilot_user_object, include_snippy: false)
    end

    sig { override.returns(T::Boolean) }
    def copilot_for_business_enabled?
      has_copilot_standalone_business? || orgs_using_copilot_for_business.any?
    end

    # This check is currently only used when user is enterprise managed, so use
    # the enterprise managed business helper first.
    # This allows us to find users who are EMUs but also guest collaborators;
    # the `businesses` method will not return businesses that the user is a guest collaborator for.
    # Guest collaborators only exist in EMU land.
    sig { returns(T::Boolean) }
    memoize def has_enterprise_seat?
      emu_business = user_object.enterprise_managed_business
      return true if emu_business.present? && Copilot::Seat.for_business(emu_business).any? { |seat| seat.assigned_user_id == user_object.id }


      user_object.businesses(include_unaffiliated: true).any? do |b|
        Copilot::Seat.for_business(b).any? { |seat| seat.assigned_user_id == user_object.id }
      end
    end

    sig { override.returns(T::Boolean) }
    def can_emit_usage?; false; end

    sig { returns(T::Boolean) }
    memoize def has_pro_subscription?
      public_subscription_item = copilot_active_subscription_item
      return false unless public_subscription_item

      product_identifier = public_subscription_item.product_identifier
      product_identifier.product_key == ::Copilot::INDIVIDUAL_PRO_PRODUCT_KEY
    end

    sig { returns(T::Boolean) }
    memoize def has_pro_plus_subscription?
      public_subscription_item = copilot_active_subscription_item
      return false unless public_subscription_item

      product_identifier = public_subscription_item.product_identifier
      product_identifier.product_key == ::Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY
    end

    sig { returns(T::Boolean) }
    memoize def has_max_subscription?
      public_subscription_item = copilot_active_subscription_item
      return false unless public_subscription_item

      product_identifier = public_subscription_item.product_identifier
      product_identifier.product_key == ::Copilot::INDIVIDUAL_MAX_PRODUCT_KEY
    end

    sig { void }
    def invalidate_quota_cache!
      return unless user_object.feature_flag_enabled?(:copilot_quota_cache_version, default: false)

      CopilotLimiter::Twirp.quota_client.delete_consumptive_user(
        copilot_tracking_id: user_object.analytics_tracking_id,
      )
    end

    sig { params(flag_name: Symbol, default: T::Boolean).returns(T::Boolean) }
    def feature_flag_enabled_include_parents?(flag_name, default:)
      ff_sources = [self] + self.copilot_organizations + self.copilot_businesses
      ff_sources.compact.uniq.any? { |source| source.feature_flag_enabled?(flag_name, default:) }
    end

    sig { override.returns(Promise[T::Array[Targeting::Targetable]]) }
    def async_targetable_parents
      async_businesses_and_orgs_using_copilot_for_business.then do |businesses_and_orgs|
        businesses = T.cast(businesses_and_orgs[:businesses], T::Array[Copilot::Business])
        organizations = T.cast(businesses_and_orgs[:organizations], T::Array[Copilot::Organization])
        # If a seat is assigned directly by the business, it is a direct parent of the user and does
        # not go through the organization
        direct_businesses = businesses.select { |business| organizations.none? { |org| org.copilot_business&.business_object == business.business_object } }

        organizations + direct_businesses
      end
    end

    sig { override.returns(T::Hash[Targeting::Attribute, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def targetable_attributes
      {}
    end
  end
end
