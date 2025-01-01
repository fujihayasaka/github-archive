# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd::Email
  class MemberFeatureRequestRendererTest < GitHub::TestCase

    setup { skip unless GitHub.billing_enabled? }

    fixtures do
      @admin = create(:user, :verified, email: "admin_growth@github.com", name: "GrowthAdmin")
      @org = create(:organization, :with_profile, plan: "free", admin: @admin, name: "GrowthOrg", profile_name: "Growth Org")

      @member = create(:user, :verified)
      @org.add_member(@member)

      @feature_request = MemberFeatureRequest::Feature::CopilotForBusiness

      @notification = create(:member_feature_request_notification, entity: @org, user: @admin, feature: @feature_request.to_s, feature_request_count: 5)
    end

    test "#render" do
      layout = Notifyd::Email::MemberFeatureRequestRenderer.new(@notification, nil).render

      assert_equal layout.headers["Message-ID"], "<GrowthOrg/feature_requests/copilot_for_business@github.com>"
      assert_equal layout.headers["List-Archive"], "https://github.com/GrowthAdmin"

      assert_equal layout.subject, "[Growth Org] New requests from members for #{Copilot.business_product_name}"

      assert_match "You have 5 new requests from members for #{Copilot.business_product_name}", layout.body
      assert_match "Members of your Growth Org organization want #{Copilot.business_product_name}", layout.body

      assert_match "You have 5 new requests from members for #{Copilot.business_product_name}", layout.text_body
      assert_match "5 members of your Growth Org organization have requested access to #{Copilot.business_product_name}", layout.text_body

      assert_match "/organizations/GrowthOrg/settings/member_feature_requests", layout.text_body

      assert_equal layout.from&.email, "noreply@noreply.github.com"
      assert_equal layout.from&.name, "GitHub"
      assert_equal layout.to, "\"GrowthAdmin\" <admin_growth@github.com>"

      assert_equal layout.reasons_to_words, {}
      assert_equal layout.url, "https://github.com/organizations/#{@org}/settings/member_feature_requests"

      expected_unsubscribe_url_templates = Notifyd::Proto::Layouts::Email::UnsubscribeUrlTemplates.new(
        footer: "https://github.com/notifications/unsubscribe-auth/{token}",
        header: "https://github.com/notifications/unsubscribe/one-click/{token}"
      )
      assert_equal layout.unsubscribe_url_templates, expected_unsubscribe_url_templates
    end

    test "#render a different link for enterprise admin for Copilot for Business" do
      business = create(:business, owners: [@admin])
      org = create(:organization, admins: [@admin], business: business)
      notification = create(:member_feature_request_notification, entity: org, user: @admin, feature: MemberFeatureRequest::Feature::CopilotForBusiness.to_s, feature_request_count: 5)
      layout = Notifyd::Email::MemberFeatureRequestRenderer.new(notification, nil).render

      assert_match "Allow this organization to assign seats", layout.body
      assert_match "/organizations/#{org}/settings/copilot/seat_management", layout.body

      assert_match "Allow this organization to assign seats", layout.text_body
      assert_match "/organizations/#{org}/settings/copilot/seat_management", layout.text_body
    end

    test "#render copilot research message" do
      layout = Notifyd::Email::MemberFeatureRequestRenderer.new(@notification, nil).render

      assert_match "Research has found GitHub Copilot helps", layout.body
      assert_match "Research has found GitHub Copilot helps", layout.text_body
    end

    test "renders enterprise_notification if type is business" do
      business = create(:business, owners: [@admin], name: "Growth Business")
      notification = create(:member_feature_request_notification, entity: business, user: @admin, feature: MemberFeatureRequest::Feature::CopilotForBusiness.to_s, feature_request_count: 5)

      layout = Notifyd::Email::MemberFeatureRequestRenderer.new(notification, nil).render

      assert_equal layout.subject, "[Growth Business] New requests from admins for #{Copilot.business_product_name}"
      assert_match "Organizations in your Growth Business enterprise want #{Copilot.business_product_name}", layout.body
      assert_match "enterprises/#{business.display_login}/settings/copilot", layout.body
      assert_match "settings/notifications", layout.body
    end
  end
end
