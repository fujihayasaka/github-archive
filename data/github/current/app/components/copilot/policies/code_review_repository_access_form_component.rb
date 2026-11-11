# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CodeReviewRepositoryAccessFormComponent < ApplicationComponent
      include GitHub::Memoizer

      sig { returns(::Business) }
      attr_reader :configurable

      sig { params(configurable: (::Business), return_to: T.nilable(String), can_write: T::Boolean).void }
      def initialize(configurable:, return_to: nil, can_write: true)
        @configurable = configurable
        @return_to = return_to
        @can_write = T.let(can_write, T::Boolean)
      end

      sig { returns(T::Boolean) }
      def render?
        configurable.feature_flag_enabled?(:copilot_code_review_policy, default: false) && logged_in?
      end

      private

      sig { returns(String) }
      def submit_path
        if FeatureFlag.vexi.enabled?(:enterprise_ai_controls, configurable, default: false) && @return_to.present?
          update_code_review_repository_access_enterprise_path(configurable, return_to: @return_to)
        else
          update_code_review_repository_access_enterprise_path(configurable)
        end
      end

      sig { returns(T::Boolean) }
      def checked?
        !configurable.code_review_repository_access_enabled?
      end

      sig { returns(Copilot::Business) }
      memoize def copilot_object
        Copilot::Business.new(configurable)
      end
    end
  end
end
