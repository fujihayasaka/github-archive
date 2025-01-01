# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CodeReviewRepositoryAccessFormComponent < ApplicationComponent
      include GitHub::Memoizer

      sig { returns(::Business) }
      attr_reader :configurable

      sig { params(configurable: (::Business)).void }
      def initialize(configurable:)
        @configurable = configurable
      end

      sig { returns(T::Boolean) }
      def render?
        configurable.feature_flag_enabled?(:copilot_code_review_policy, default: false) && logged_in?
      end

      private

      sig { returns(String) }
      def submit_path
        update_code_review_repository_access_enterprise_path(configurable)
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
