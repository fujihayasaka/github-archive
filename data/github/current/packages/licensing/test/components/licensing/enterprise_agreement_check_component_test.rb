# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::EnterpriseAgreementCheckComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "Success rendered with no enterprise agreement" do
    business = create(:business)
    business.customer.stub(:has_active_vss_enterprise_agreement?, false) do
      render_inline(Licensing::EnterpriseAgreementCheckComponent.new(business: business), allowed_queries: 1)
      assert_test_selector("enterprise-agreement-check", text: "No active Enterprise Agreement with VSS seats")
    end
  end

  test "Error rendered with enterprise agreement" do
    business = create(:business)
    business.customer.stub(:has_active_vss_enterprise_agreement?, true) do
      render_inline(Licensing::EnterpriseAgreementCheckComponent.new(business: business), allowed_queries: 1)
      assert_test_selector("enterprise-agreement-check", text: "There is an active Enterprise Agreement with VSS seats")
    end
  end
end
