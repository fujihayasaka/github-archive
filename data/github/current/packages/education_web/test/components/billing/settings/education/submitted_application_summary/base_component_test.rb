# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Settings::Education
  class TestComponent < SubmittedApplicationSummary::BaseComponent
    def progress_bar_component
      render(Primer::Beta::ProgressBar.new(size: :large)) do |component|
        component.with_item(bg: :done, percentage: 100)
      end
    end

    def time_words
      "Submitted 200 years ago"
    end
  end

  class SubmittedApplicationSummaryBaseComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    context "when the feature is enabled" do
      test "it renders the submitted application summary" do
        enable_feature_flag("education-dev-pack-application")
        submitted_application = create(:education_developer_pack_application_metadata, :approved)

        render_inline(
          TestComponent.new(submitted_application:),
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
          TestComponent.new(submitted_application:),
          allowed_queries: 1,
        )

        refute_component_rendered
      end
    end
  end
end
