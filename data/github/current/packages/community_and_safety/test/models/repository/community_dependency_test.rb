# typed: true
# frozen_string_literal: true

require "test_helper"

class CommunityDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @user = create(:user)
    @rando = create(:user)
    @repo = create(:repository, owner: @owner)

    @business_org = create(:enterprise_linked_organization)
    @business = @business_org.business
    @business_owner = @business.owners.first
    @business_repo = create(:private_repository, owner: @business_org, from_example: :contributing_support_and_code_of_conduct)

    @licensed_repo = create(:repository, from_example: :license_markdown)
    @licensed_repo.set_licenses

    @three_licenses = create(:repository, from_example: :three_licenses)
    @three_licenses.set_licenses

    @contributing_repo = create(:repository, from_example: :contributing_support_and_code_of_conduct)

    @private_contributing_repo = create(:private_repository, from_example: :contributing_support_and_code_of_conduct)
  end

  context "#can_view_community_insights?" do
    test "requires maintain+ for users" do
      @repo.add_member(@user)

      assert @repo.can_view_community_insights?(@owner)
      assert @repo.can_view_community_insights?(@user)
      refute @repo.can_view_community_insights?(@rando)
    end

    test "true for user without a verified email address" do
      @owner.emails.map(&:unverify!)
      assert @repo.can_view_community_insights?(@owner)
    end

    test "returns false for a nil actor" do
      refute @repo.can_view_community_insights?(nil)
    end

    test "returns true for admin if feature flag enabled" do
      assert @repo.can_view_community_insights?(@owner)
    end
  end

  context "#license" do
    test "when multiple licenses, returns 'mit' license as best match" do
      assert_equal "mit", @three_licenses.license.key
    end
  end

  context "#licenses" do
    test "when unlicensed, returns empty array" do
      assert_empty @repo.licenses
    end

    test "when licensed, returns array of licenses" do
      assert_equal ["mit"], @licensed_repo.licenses.map(&:key)
    end
  end

  context "#contributing" do
    test "when no contributing file, returns false" do
      assert_nil @repo.preferred_contributing
      refute @repo.detect_contributing
    end

    test "when there is a contributing file in a public repo, detect returns true" do
      assert @contributing_repo.preferred_contributing
      assert @contributing_repo.detect_contributing
    end

    test "when there is a contributing file in a private repo, detect returns true" do
      assert @private_contributing_repo.preferred_contributing
      assert @private_contributing_repo.detect_contributing
    end

    test "when there is a contributing file in a private repo in an enterprise, returns true" do
      assert @business_repo.detect_contributing
      assert @business_repo.preferred_contributing
    end
  end
end
