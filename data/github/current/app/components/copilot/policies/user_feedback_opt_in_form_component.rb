# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class UserFeedbackOptInFormComponent < ApplicationComponent
      include GitHub::Memoizer

      sig { returns(::Business) }
      attr_reader :configurable

      sig { params(configurable: (::Business)).void }
      def initialize(configurable:)
        @configurable = configurable
      end

      sig { returns(T::Boolean) }
      def render?
        logged_in?
      end

      private

      sig { returns(String) }
      def submit_path
        update_settings_copilot_policy_enterprise_path(configurable)
      end

      sig { returns(Copilot::Business) }
      memoize def copilot_object
        Copilot::Business.new(configurable)
      end
    end
  end
end
