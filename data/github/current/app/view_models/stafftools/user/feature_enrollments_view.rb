# typed: true
# frozen_string_literal: true

module Stafftools
  module User
    class FeatureEnrollmentsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      attr_reader :user

      def page_title
        "#{user.login} - #{page_heading}"
      end

      def page_heading
        "Feature & Beta Enrollments"
      end

      def prerelease_agreement_signed?
        !!prerelease_agreement
      end

      def prerelease_agreement
        user && user.prerelease_agreement
      end

      def feature_enrollments
        Feature.available_to(user).to_a
      end

      def enrolled?(feature, user)
        feature.enrolled?(user)
      end
    end
  end
end
