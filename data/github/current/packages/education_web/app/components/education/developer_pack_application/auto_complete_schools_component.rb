# typed: strict
# frozen_string_literal: true

module Education
  module DeveloperPackApplication
    class AutoCompleteSchoolsComponent < ApplicationComponent
      include Education::DeveloperPackApplication::SchoolHelper

      sig do
        params(
          schools: T.untyped,
          user_has_two_factor_auth_enabled: T::Boolean,
          user_verified_emails: T::Array[String],
        ).void
      end
      def initialize(schools:, user_has_two_factor_auth_enabled:, user_verified_emails:)
        @schools = schools
        @user_has_two_factor_auth_enabled = user_has_two_factor_auth_enabled
        @user_verified_emails = user_verified_emails
      end

      sig { returns(String) }
      def call
        safe_join(
          @schools.map do |school|
            render Primer::Beta::AutoComplete::Item.new(
              value: school["name"],
              classes: "typeahead-result js-school-autocomplete-result-selection",
              data: {
                selected_school_id: school["school_id"],
                school_name: school["name"],
                two_factor_required: user_needs_2fa_turned_on?(school:, user_has_two_factor_auth_enabled:),
                override_distance_limit: school["override_distance_limit"],
                camera_required: !school_allows_file_uploads?(school:),
                email_domains: email_domains(school:),
                user_too_far_from_school: user_too_far_from_school?(school:),
                user_has_email_for_school: user_has_email_for_school?(
                  school:,
                  user_verified_emails:,
                ),
                test_selector: "autocomplete-item-school-#{school['school_id']}",
              },
            ) do
              school["name"]
            end
          end,
        )
      end

      private

      sig { returns(T::Boolean) }
      attr_reader :user_has_two_factor_auth_enabled

      sig { returns(T::Array[String]) }
      attr_reader :user_verified_emails
    end
  end
end
