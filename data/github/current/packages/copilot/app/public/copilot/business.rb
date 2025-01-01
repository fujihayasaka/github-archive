# typed: strict
# frozen_string_literal: true

module Copilot
  # This wraps ::Business with Copilot-specific logic.
  class Business < SimpleDelegator

    include Metrics
    include Copilot::Billable
    include ::Billing::Abuse::Copilot::AuthAndCapture
    include Copilot::Businesses::SeatManagement
    include Copilot::Businesses::Usage
    include Copilot::Helpers
    include Businesses::Billing
    include Businesses::CsvExport
    include Businesses::InstrumentationDetails
    include Businesses::Licensing
    include Businesses::Mailable
    include Businesses::Settings
    include Businesses::Trials

    delegate \
      :display_login,
      :feature_enabled?,
      :organizations,
      :slug,
      :spammy?,
      :suspended?,
      :feature_enabled?,
      to: :business_object

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

    sig { params(user: ::User).returns(T::Boolean) }
    def has_seat_for?(user)
      Copilot::Seat.for_business_user(business_object, user).any?
    end
  end
end
