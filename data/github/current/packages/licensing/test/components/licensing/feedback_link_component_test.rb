# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::FeedbackLinkComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @business = create(:business)
    @owner = @business.owners.first
  end

  context "Feedback component", skip_enterprise: true do
    test "renders banner" do
      survey_id = "test-survey-id"
      description = "test description"

      as @owner
      result = render_inline Licensing::FeedbackLinkComponent.new(business_slug: @business.slug, survey_id: survey_id), allowed_queries: 1 do |component|
        component.with_description { description }
      end

      assert_test_selector survey_id, count: 1
      assert_text description
    end

    test "does not render banner if survey is dismissed by user" do
      survey_id = "test-survey-id"
      target_setting_key = Licensing::FeedbackLinkComponent.dismissal_setting_key(business_slug: @business.slug, survey_id: survey_id)

      Billing::Kv.store.set(target_setting_key, "true")
      assert Billing::Kv.store.exists(target_setting_key).value!

      description = "test description"

      as @owner
      render_inline Licensing::FeedbackLinkComponent.new(business_slug: @business.slug, survey_id: survey_id), allowed_queries: 1 do |component|
        component.with_description { description }
      end

      refute_test_selector survey_id
    end
  end
end
