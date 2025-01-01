# typed: strict
# frozen_string_literal: true

module Copilot
  # This wraps ::Business with Copilot-specific logic.
  class Business < SimpleDelegator

    include Metrics
    include Copilot::Billable
    include Copilot::AuthAndCapture
    include Copilot::Businesses::SeatManagement
    include Copilot::Helpers
    include Businesses::Billing
    include Businesses::ContentExclusion
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
      to: :business_object

    sig { returns(T::Boolean) }
    def eligible_for_first_run_flow?
      copilot_config = Copilot::Configuration.find_by(configurable: business_object)

      return true if copilot_config.nil?

      # Even if a specific owner hasn't been opted in, any owner of a business should be able to see the first run flow
      return true if copilot_config.unconfigured? && business_object.owners.any? { |owner| owner.feature_enabled?(:copilot_purchase_flow_refresh) }

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
      T.must(business_object.id)
    end

    sig { override.returns(::Business) }
    def configurable_object
      business_object
    end

    sig { override.returns(::Business) }
    def business_object
      T.cast(__getobj__, ::Business)
    end
  end
end
