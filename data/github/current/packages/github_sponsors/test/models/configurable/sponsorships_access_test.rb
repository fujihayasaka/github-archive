# typed: true
# frozen_string_literal: true

require "test_helper"

class Configurable::SponsorshipsAccessTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @enterprise = create(:business, owners: [@admin])
    @owned_org, @standalone_org = create_pair(:organization, admin: @admin)

    @enterprise.add_organization @owned_org
  end

  if GitHub.sponsors_enabled?
    test "users have sponsorship access by default" do
      assert_predicate @admin, :has_sponsorships_access?
    end

    test "standalone orgs have sponsorship access by default" do
      assert_predicate @standalone_org.reload, :has_sponsorships_access?
    end

    test "owned orgs do not have sponsorship access by default" do
      refute_predicate @owned_org.reload, :has_sponsorships_access?
    end

    test "owned orgs can be granted sponsorship access" do
      @owned_org.grant_sponsorships_access(actor: @admin)

      assert_predicate @owned_org.reload, :has_sponsorships_access?
    end

    test "owned orgs can have sponsorship access revoked" do
      @owned_org.grant_sponsorships_access(actor: @admin)
      assert_predicate @owned_org.reload, :has_sponsorships_access?

      @owned_org.revoke_sponsorships_access(actor: @admin)
      refute_predicate @owned_org.reload, :has_sponsorships_access?
    end

    test "sibling orgs do not affect one another" do
      other_org = create :organization, admin: @admin
      @enterprise.add_organization other_org

      @owned_org.grant_sponsorships_access(actor: @admin)
      assert_predicate @owned_org.reload, :has_sponsorships_access?
      refute_predicate other_org.reload, :has_sponsorships_access?
    end
  end
end
