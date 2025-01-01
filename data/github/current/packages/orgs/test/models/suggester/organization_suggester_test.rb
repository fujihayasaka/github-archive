# typed: true
# frozen_string_literal: true

require "test_helper"

class SuggesterOrganizationSuggesterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @user = create(:user)
    @user_org = create(:organization, admin: @user)

    @billing_org = create(:organization)
    @billing_org.billing.add_manager @user, actor: @user

    @unrelated_org = create(:organization)

    @suggester = Suggester::OrganizationSuggester.new(viewer: @user, cap_filter: cap_authorizing_filter).freeze
  end

  context "mentions" do
    test "includes organization user belongs to" do
      assert @suggester.mentions.any? { |x| x[:id] == @user_org.id }
    end

    test "includes organization user billing manages" do
      assert @suggester.mentions.any? { |x| x[:id] == @billing_org.id }
    end

    test "does not include unrelated organization" do
      refute @suggester.mentions.any? { |x| x[:id] == @unrelated_org.id }
    end
  end
end
