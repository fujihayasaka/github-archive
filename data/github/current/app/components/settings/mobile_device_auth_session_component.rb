# typed: true
# frozen_string_literal: true

module Settings
  class MobileDeviceAuthSessionComponent < ApplicationComponent
    include MobileDeviceHelper

    def initialize(device:, style:, oauth_access: nil)
      @device = device
      @style = style
      @oauth_access = oauth_access
    end

    def style
      @style
    end

    def device_name
      @device.device_name
    end

    def device_model
      get_device_model(@device.device_model)
    end

    def created_at
      if @oauth_access&.created_at
        Time.at(@oauth_access&.created_at)
      else
        Time.at(@device.created_at_time.seconds)
      end
    end

    def last_authenticated_at
      if @device.last_used_at_time&.seconds
        Time.at(@device.last_used_at_time.seconds)
      end
    end

    def last_accessed_at
      if @oauth_access&.accessed_at
        Time.at(@oauth_access&.accessed_at)
      end
    end

    def formatted_time(time)
      Time.at(time).strftime("%b %-d, %Y")
    end
  end
end
