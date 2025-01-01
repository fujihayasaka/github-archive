# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Settings::Education
  class SubmittedApplicationSummaryApprovedComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    context "when the feature is enabled" do
      test "it renders the submitted application summary" do
        enable_feature_flag("education-dev-pack-application")
        submitted_application = create(:education_developer_pack_application_metadata, :approved)

        render_inline(
          Billing::Settings::Education::SubmittedApplicationSummary::ApprovedComponent.new(
            submitted_application:,
          ),
          allowed_queries: 1,
        )

        assert_component_rendered
      end
    end

    context "when the feature is disabled" do
      test "it does not render the submitted application summary" do
        disable_feature_flag("education-dev-pack-application")
        submitted_application = create(:education_developer_pack_application_metadata, :approved)

        render_inline(
          Billing::Settings::Education::SubmittedApplicationSummary::ApprovedComponent.new(
            submitted_application:,
          ),
          allowed_queries: 1,
        )

        refute_component_rendered
      end
    end
  end
end
