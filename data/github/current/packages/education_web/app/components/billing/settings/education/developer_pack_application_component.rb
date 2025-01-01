# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class DeveloperPackApplicationComponent < ApplicationComponent
        sig { params(user: User).void }
        def initialize(user:)
          @user = user
        end

        private

        sig { returns(User) }
        attr_reader :user

        sig { returns(T::Boolean) }
        def render?
          feature_enabled_globally_or_for_user?(feature_name: "education-dev-pack-application", subject: user)
        end
      end
    end
  end
end
