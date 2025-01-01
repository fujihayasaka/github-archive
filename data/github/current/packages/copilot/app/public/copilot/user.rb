# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Copilot
  # This is a wrapper around the ::User class.
  # It adds in methods related to Copilot
  class User < SimpleDelegator

    include GitHub::Memoizer
    include Copilot::Metrics
    include Copilot::Abuse
    include Copilot::AuthAndCapture
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
    include Copilot::Users::Policies
    include Copilot::Users::CodingGuidelines
    include Copilot::Users::CodeReview

    delegate \
      :disabled?,
      :feature_enabled?,
      :is_enterprise_managed?,
      :organizations,
      to: :user_object

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
  end
end
