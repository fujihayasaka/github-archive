# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module BusinessUserAccountActivity
      def self.business_user_account_activity_enabled?
        !Rails.env.test? || ENV["ENABLE_BUSINESS_USER_ACCOUNT_ACTIVITY_IN_TESTS"] == "true"
      end
    end
  end
end
