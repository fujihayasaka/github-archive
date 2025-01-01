# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Fanout
    module Types
      class SessionTest < GitHub::TestCase
        fixtures do
          if GitHub.enterprise?
            @biz = create(:global_business)
            @user = create(:user, business: @biz)
          else
            @biz = create(:business, :enterprise_managed)
            @user = create(:emu, business: @biz)
          end
          @org = create(:organization, business: @biz)
        end

        context ".from_tenant" do
          test "returns correct type for business" do
            assert_equal TenantScope::Business, TenantScope.from_tenant(@biz)
          end

          test "returns correct type for organization" do
            assert_equal TenantScope::Organization, TenantScope.from_tenant(@org)
          end

          test "returns correct type for user" do
            assert_equal TenantScope::User, TenantScope.from_tenant(@user)
          end
        end
      end
    end
  end
end
