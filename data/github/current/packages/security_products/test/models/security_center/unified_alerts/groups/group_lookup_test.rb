# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module UnifiedAlerts
    module Groups
      class GroupLookupTest < GitHub::TestCase
        extend T::Sig

        fixtures do
          @biz = create(:business)
          @org_admin = create(:user)
          @org = create(:organization, business: @biz, admin: @org_admin)
          @repo = create(:private_repository, owner: @org)
        end

        test "creates ByTool group from group key" do
          assert GroupLookup.from("tool", scope: @org, user: @org_admin).is_a?(ByTool)
        end

        test "creates BySeverity group from group key" do
          assert GroupLookup.from("severity", scope: @org, user: @org_admin).is_a?(BySeverity)
        end

        test "creates ByRepository group from group key" do
          assert GroupLookup.from("repo", scope: @org, user: @org_admin).is_a?(ByRepository)
        end

        test "creates ByRepositoryVisibility group from group key" do
          assert GroupLookup.from("repo.visibility", scope: @org, user: @org_admin).is_a?(ByRepositoryVisibility)
        end

        test "creates ByTeam group from group key" do
          assert GroupLookup.from("team", scope: @org, user: @org_admin).is_a?(ByTeam)
        end

        test "creates ByTopic group from group key" do
          assert GroupLookup.from("topic", scope: @org, user: @org_admin).is_a?(ByTopic)
        end

        test "creates ByCustomProperty group from group key" do
          assert GroupLookup.from("repo.props.test-property", scope: @org, user: @org_admin).is_a?(ByCustomProperty)
        end

        test "creates ByAdvisory group from group key" do
          assert GroupLookup.from("dependabot.advisory", scope: @org, user: @org_admin).is_a?(ByAdvisory)
        end

        test "returns nil for unknown group key" do
          assert_nil GroupLookup.from("foo", scope: @org, user: @org_admin)
        end
      end
    end
  end
end
