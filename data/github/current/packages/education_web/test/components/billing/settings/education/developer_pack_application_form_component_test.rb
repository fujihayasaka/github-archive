# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Settings::Education
  class DeveloperPackApplicationFormComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    setup { skip if GitHub.enterprise? }

    context "when the feature is enabled" do
      test "it renders the application form" do
        enable_feature_flag("education-dev-pack-application")
        form_errors = {}
        form_values = {}
        user = create(:user)

        render_inline(
          Billing::Settings::Education::DeveloperPackApplicationFormComponent.new(form_errors:, form_values:, user:),
          allowed_queries: 1,
        )

        assert_component_rendered
      end
    end

    context "when the feature is disabled" do
      test "it does not render the application form" do
        disable_feature_flag("education-dev-pack-application")
        form_errors = {}
        form_values = {}
        user = create(:user)

        render_inline(
          Billing::Settings::Education::DeveloperPackApplicationFormComponent.new(form_errors:, form_values:, user:),
          allowed_queries: 1,
        )

        refute_component_rendered
      end
    end

    context "when the current form values has the form variant of initial_form" do
      context "when there are no form errors" do
        context "when a new school is not being added" do
          test "it renders the upload proof form" do
            enable_feature_flag("education-dev-pack-application")
            form_errors = {}
            form_values = { form_variant: "initial_form" }
            user = create(:user)

            render_inline(
              Billing::Settings::Education::DeveloperPackApplicationFormComponent.new(form_errors:, form_values:, user:),
              allowed_queries: 1,
            )

            assert_component_rendered
          end
        end
      end
    end

    context "when the current form values has the form variant of new_school_form" do
      context "when there are no form errors" do
        test "it renders the upload proof form" do
          enable_feature_flag("education-dev-pack-application")
          form_errors = {}
          form_values = { form_variant: "new_school_form" }
          user = create(:user)

          render_inline(
            Billing::Settings::Education::DeveloperPackApplicationFormComponent.new(form_errors:, form_values:, user:),
            allowed_queries: 1,
          )

          assert_component_rendered
        end
      end
    end
  end
end
