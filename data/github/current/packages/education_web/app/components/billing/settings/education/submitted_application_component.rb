# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class SubmittedApplicationComponent < ApplicationComponent
        SUMMARY_COMPONENT_MAPPING = T.let({
          approved: Education::SubmittedApplicationSummary::PendingComponent,
          pending: Education::SubmittedApplicationSummary::PendingComponent,

          coupon_applied: Education::SubmittedApplicationSummary::ApprovedComponent,

          denied: Education::SubmittedApplicationSummary::DeniedComponent,
          revoked: Education::SubmittedApplicationSummary::DeniedComponent,

          expired: Education::SubmittedApplicationSummary::ExpiredComponent,
        }.freeze, T::Hash[Symbol, T.untyped])

        sig { params(submitted_application: EducationDeveloperPackApplicationMetadata).void }
        def initialize(submitted_application:)
          @submitted_application = submitted_application
        end

        private

        sig { returns(EducationDeveloperPackApplicationMetadata) }
        attr_reader :submitted_application

        sig { returns(User) }
        def user
          T.must(submitted_application.user)
        end

        sig { returns(T::Boolean) }
        def render?
          feature_enabled_globally_or_for_user?(feature_name: "education-dev-pack-application", subject: user)
        end

        sig { returns(String) }
        def summary_content_component
          component = SUMMARY_COMPONENT_MAPPING[submitted_application.status]

          render component.new(submitted_application:)
        end
      end
    end
  end
end
