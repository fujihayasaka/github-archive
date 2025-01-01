# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  class RepositoryCodeSecurityPolicyNotificationComponentTest < GitHub::TestCase
    include GitHub::ComponentTestHelpers

    setup do
      GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
      @biz = create(:global_business)
      @org = create(:organization, business: @biz)
    end

    context "#render?" do
      test "it renders with a business" do
        render_inline RepositoryCodeSecurityPolicyNotificationComponent.new(@biz), without_query_count: true

        assert_text "Managed by #{@biz.name}", normalize_ws: true
      end

      test "it renders with an org" do
        render_inline RepositoryCodeSecurityPolicyNotificationComponent.new(@org), without_query_count: true

        assert_text "Managed by #{@org.name}", normalize_ws: true
      end
    end
  end
end
