# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class MobileHydroEvent < Platform::Inputs::Base
      description "Details about a hydro event."
      mobile_only true

      argument :app_element, Enums::MobileAppElement, "The element of the event that took place on.", required: true
      argument :app_type, Enums::MobileAppType, "The app type the event took place on.", required: true
      argument :device_type, Enums::MobileDeviceType, "The device type the event took place on.", required: true
      argument :action, Enums::MobileAppAction, "The action that was performed.", required: true
      argument :performed_at, Scalars::DateTime, "The time the event was performed.", required: true
      argument :subject_type, Enums::MobileSubjectType, "The device type the event took place on.", required: false
      argument :context, Enums::MobileEventContext, "Extra context provided for the mobile event", required: false, as: :extra_context
    end
  end
end
