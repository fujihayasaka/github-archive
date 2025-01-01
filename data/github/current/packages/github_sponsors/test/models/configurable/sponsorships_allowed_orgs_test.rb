# typed: true
# frozen_string_literal: true

require "test_helper"

class Configurable::SponsorshipsAllowedOrgsTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @enterprise = create(:business, owners: [@admin])
    @owned_org1, @owned_org2 = create_pair(:organization, admin: @admin)
    @standalone_org = create(:organization, admin: @admin)

    @enterprise.add_organization @owned_org1
    @enterprise.add_organization @owned_org2
  end

  test "returns empty list when no orgs have been granted access" do
    result = @enterprise.sponsorships_allowed_orgs

    assert result.empty?
  end

  test "returns org ids that have been granted access" do
    @owned_org1.grant_sponsorships_access(actor: @admin)
    @owned_org1.reload

    result = @enterprise.reload.sponsorships_allowed_orgs
    assert result.include? @owned_org1.id
    refute result.include? @owned_org2.id
    refute result.include? @standalone_org.id
  end
end
