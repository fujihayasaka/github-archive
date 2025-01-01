# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::Settings::Education
  class OverviewComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    context "when the feature is enabled" do
      context "when the user does not have a student or faculty coupon" do
        test "it renders with an enabled button" do
          enable_feature_flag("education-dev-pack-application")
          user = create(:user)

          render_inline(Billing::Settings::Education::OverviewComponent.new(user:), allowed_queries: 4)

          assert_component_rendered
          assert_test_selector("devpack-apply-button", text: "Start an application") { |btn| refute btn.disabled? }
        end
      end

      context "when the user has a student coupon" do
        test "it renders with a disabled button" do
          enable_feature_flag("education-dev-pack-application")
          user = create(:user, :with_student_developer_pack_coupon)

          render_inline(Billing::Settings::Education::OverviewComponent.new(user:), allowed_queries: 3)

          assert_component_rendered
          assert_test_selector("devpack-apply-button", text: "Start an application") { |btn| assert btn.disabled? }
          assert_test_selector("edu-apply-text", text: "You have a current student coupon applied. See below for more details.")
        end
      end

      context "when the user has a faculty coupon" do
        test "it renders with a disabled button" do
          enable_feature_flag("education-dev-pack-application")
          user = create(:user, :with_faculty_developer_pack_coupon)

          render_inline(Billing::Settings::Education::OverviewComponent.new(user:), allowed_queries: 3)

          assert_component_rendered
          assert_test_selector("devpack-apply-button", text: "Start an application") { |btn| assert btn.disabled? }
          assert_test_selector("edu-apply-text", text: "You have a current faculty coupon applied. See below for more details.")
        end
      end

      context "when the user has a current pending application" do
        test "it renders with a disabled button" do
          enable_feature_flag("education-dev-pack-application")
          user = create(:user)
          create(:education_developer_pack_application_metadata, user:)

          render_inline(Billing::Settings::Education::OverviewComponent.new(user:), allowed_queries: 5)

          assert_component_rendered
          assert_test_selector("devpack-apply-button", text: "Start an application") { |btn| assert btn.disabled? }
          assert_test_selector("edu-apply-text", text: "You have a current pending application. See below for more details.")
        end
      end
    end

    context "when the feature is disabled" do
      test "it does not render" do
        disable_feature_flag("education-dev-pack-application")
        user = create(:user)

        render_inline(Billing::Settings::Education::OverviewComponent.new(user:), allowed_queries: 1)

        refute_component_rendered
      end
    end
  end
end
