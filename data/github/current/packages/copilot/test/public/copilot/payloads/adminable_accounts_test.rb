# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Payloads::AdminableAccountsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    # multi admin is an admin of both the org and the enterprise
    @multi_admin = create(:user, skip_organization_add: true)
    @enterprise_org = create(:organization, admins: [@multi_admin], plan: "business_plus")
    @enterprise_business = create(:business, :with_self_serve_payment, owners: [@multi_admin], organizations: [@enterprise_org])
    @enterprise_business.enable_self_serve_payments
  end

  test "#to_a returns an array of adminable accounts" do
    accounts = Copilot::Payloads::AdminableAccounts.new(@multi_admin).to_a
    sorted = [@enterprise_business.slug.downcase, @enterprise_org.display_login.downcase].sort

    assert_equal 2, accounts.size
    assert_equal T.must(accounts.first)[:slug], sorted.first
    assert_equal T.must(accounts.last)[:slug], sorted.second
  end

  test "#to_h returns a hash of adminable accounts" do
    accounts = Copilot::Payloads::AdminableAccounts.new(@multi_admin).to_h

    assert_equal T.must(accounts[:organizations]).count, 1
    assert_equal T.must(accounts[:businesses]).count, 1
  end
end unless GitHub.enterprise?
