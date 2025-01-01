# typed: strict
# frozen_string_literal: true

module Copilot
  # This wraps ::Business with Copilot-specific logic.
  class Business < SimpleDelegator
    extend T::Sig

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

    delegate :display_login, :slug, :spammy?, :suspended?, :feature_enabled?, to: :business_object

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
