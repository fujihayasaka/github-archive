# typed: strict
# frozen_string_literal: true

module OnboardingTasks
  module Businesses
    class CreateOverviewReadme < Base
      sig { override.returns(String) }
      def title
        "Create an overview README"
      end

      sig { override.returns(String) }
      def task_link
        enterprise_path(business)
      end

      sig { override.returns(T::Boolean) }
      def verify_task
        business.long_description.present?
      end

      sig { returns(T::Boolean) }
      def completed?
        super && verify_task
      end

      sig { override.returns(T.nilable(String)) }
      def icon_path
        nil
      end
    end
  end
end
