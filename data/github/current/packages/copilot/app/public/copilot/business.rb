# typed: strict
# frozen_string_literal: true

module Copilot
  # This wraps ::Business with Copilot-specific logic.
  class Business < SimpleDelegator
    include Limits
    include Metrics
    include Copilot::Billable
    include ::Billing::Abuse::Copilot::AuthAndCapture
    include Copilot::Businesses::SeatManagement
    include Copilot::Helpers
    include Businesses::ActivityExport
    include Businesses::Billing
    include Businesses::InstrumentationDetails
    include Businesses::Licensing
    include Businesses::Mailable
    include Businesses::Settings
    include Businesses::Trials
    include Targeting::Targetable

    delegate \
      :display_login,
      :organizations,
      :safe_profile_name,
      :slug,
      :spammy?,
      :suspended?,
      :feature_flag_enabled?,
      :feature_flag_enabled_or_raise?,
      to: :business_object

    # Trial businesses can assign up to 50 business-owned Copilot seats.
    limits :trial_copilot_seats,
      to: ::Billing::EnterpriseCloudTrial::INITIAL_BUSINESS_OWNED_COPILOT_LICENSE_COUNT,
      reached_when: -> {
        T.bind(self, Copilot::Business)
        return false unless business_object.trial?

        current_count = Copilot::Seat.business_owned(business_object).count
        current_count >= trial_copilot_seats_limit
      },
      reached_message: "Trial accounts are limited to #{::Billing::EnterpriseCloudTrial::INITIAL_BUSINESS_OWNED_COPILOT_LICENSE_COUNT} enterprise-assigned Copilot seats."

    sig { returns(T::Boolean) }
    def eligible_for_first_run_flow?
      return false if business_object.digital_front_door?

      copilot_config = Copilot::Configuration.find_by(configurable: business_object)

      return true if copilot_config.nil?

      # Even if a specific owner hasn't been opted in, any owner of a business should be able to see the first run flow
      return true if copilot_config.unconfigured?

      false
    end

    sig { params(business: ::Business).void }
    def initialize(business)
      super
    end

    sig { returns(T::Class[T.anything]) }
    def sorbet_class
      ::Business
    end

    sig { returns(Integer) }
    def id
      T.cast(business_object.id, Integer)
    end

    sig { override.returns(::Business) }
    def configurable_object
      business_object
    end

    sig { override.returns(::Business) }
    def business_object
      T.cast(__getobj__, ::Business)
    end

    sig { returns(Copilot::Business) }
    def copilot_business_object
      self
    end

    sig { returns(String) }
    def provider_path
      Rails.application.routes.url_helpers.enterprise_path(business_object)
    end

    sig { params(user: ::User).returns(T::Boolean) }
    def has_seat_for?(user)
      Copilot::Seat.for_business_user_ids(business_object, user.id).any?
    end

    sig { params(flag_name: Symbol, default: T::Boolean).returns(T::Boolean) }
    def feature_flag_enabled_include_parents?(flag_name, default:)
      feature_flag_enabled?(flag_name, default:)
    end

    sig { override.returns(Promise[T::Array[Targeting::Targetable]]) }
    def async_targetable_parents
      Promise.resolve(T.let([], T::Array[Targeting::Targetable]))
    end

    sig { override.returns(T::Hash[Targeting::Attribute, T.untyped]) } # rubocop:disable Sorbet/ForbidTUntyped
    def targetable_attributes
      {}
    end

    sig { override.returns(::Business) }
    def internal_record
      business_object
    end

    sig { returns(T::Boolean) }
    def copilot_enablement_blocked?
      return false unless business_object.feature_flag_enabled?(:block_enterprise_copilot_activation, default: false)
      return false if business_object.feature_flag_enabled?(:allow_enterprise_copilot_activation, default: false)
      return false if business_object.invoiced?

      true
    end
  end
end
