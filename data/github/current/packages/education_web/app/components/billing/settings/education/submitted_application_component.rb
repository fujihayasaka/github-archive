# typed: strict
# frozen_string_literal: true

module Billing
  module Settings
    module Education
      class SubmittedApplicationComponent < ApplicationComponent
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
          component = if submitted_application.approved? && !submitted_application.expired?
            Billing::Settings::Education::SubmittedApplicationSummary::ApprovedComponent
          elsif submitted_application.denied?
            Billing::Settings::Education::SubmittedApplicationSummary::DeniedComponent
          elsif submitted_application.expired?
            Billing::Settings::Education::SubmittedApplicationSummary::ExpiredComponent
          else
            Billing::Settings::Education::SubmittedApplicationSummary::PendingComponent
          end

          render component.new(submitted_application:)
        end
      end
    end
  end
end
