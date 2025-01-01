# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class ByAdvisoryTest < GitHub::TestCase
        extend T::Sig

        fixtures do
          @biz = create(:business)
          @org_admin = create(:user)
          @org = create(:organization, business: @biz, admin: @org_admin)

          @vuln1 = create(:vulnerability, :with_summary)
          @vuln2 = create(:vulnerability, :with_summary)
          @vuln3 = create(:vulnerability)
        end

        context "#finalize" do
          test "translates ghsa_id into advisory title" do
            items = [
              { name: @vuln1.ghsa_id.to_s },
              { name: @vuln2.ghsa_id.to_s },
            ]
            result = ByAdvisory.new(scope: @org, user: @org_admin, group_key: "advisory").finalize(items)

            assert_equal 2, result.count
            assert_equal @vuln1.summary, result.dig(0, :name)
            assert_equal @vuln2.summary, result.dig(1, :name)
          end

          test "maintains ghsa if advisory lacks summary" do
            items = [
              { name: @vuln1.ghsa_id.to_s },
              { name: @vuln3.ghsa_id.to_s },
            ]
            result = ByAdvisory.new(scope: @org, user: @org_admin, group_key: "advisory").finalize(items)

            assert_equal 2, result.count
            assert_equal @vuln1.summary, result.dig(0, :name)
            assert_equal @vuln3.ghsa_id, result.dig(1, :name)
          end

          test "maintains ghsa if advisory doesn't exist" do
            items = [
              { name: @vuln1.ghsa_id.to_s },
              { name: "GHSA-0000-0000-0001" },
            ]
            result = ByAdvisory.new(scope: @org, user: @org_admin, group_key: "advisory").finalize(items)

            assert_equal 2, result.count
            assert_equal @vuln1.summary, result.dig(0, :name)
            assert_equal "GHSA-0000-0000-0001", result.dig(1, :name)
          end
        end
      end
    end
  end
end
