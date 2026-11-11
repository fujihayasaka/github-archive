# typed: strict
# frozen_string_literal: true

# Whether automatic user license usage upload to dotcom is enabled.
module Configurable
  module DotcomUserLicenseUsageUpload
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = T.let("dotcom_user_license_usage_upload".freeze, String)

    sig { params(actor: User).returns(T::Boolean) }
    def enable_dotcom_user_license_usage_upload(actor)
      config.enable(KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def disable_dotcom_user_license_usage_upload(actor)
      config.disable(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def dotcom_user_license_usage_upload_enabled?
      config.enabled?(KEY)
    end
  end
end
