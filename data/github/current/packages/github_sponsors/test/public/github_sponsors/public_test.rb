# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHubSponsors::PublicTest < GitHub::TestCase
  include GitHubSponsors

  context ".sponsor_status_by_sponsor_id" do
    test "returns which of the given sponsor IDs are sponsors of the specified sponsorable" do
      sponsorable = create(:organization, :sponsorable)
      active_sponsorship1 = create(:sponsorship, sponsorable: sponsorable)
      active_sponsorship2 = create(:sponsorship, sponsorable: sponsorable)
      inactive_sponsorship = create(:sponsorship, :inactive, sponsorable: sponsorable)
      other_sponsorship = create(:sponsorship)
      sponsor_ids = [active_sponsorship1.sponsor_id, active_sponsorship2.sponsor_id, inactive_sponsorship.sponsor_id,
        other_sponsorship.sponsor_id]
      viewer = create(:user)

      result = GitHubSponsors::Public.sponsor_status_by_sponsor_id(sponsor_ids, sponsorable_id: sponsorable.id,
        viewer: viewer)

      assert_instance_of Hash, result
      assert result[active_sponsorship1.sponsor_id]
      assert result[active_sponsorship2.sponsor_id]
      refute result[inactive_sponsorship.sponsor_id]
      refute result[other_sponsorship.sponsor_id]
    end

    test "considers viewer permissions for a private sponsorship from a user sponsor" do
      sponsorable = create(:user, :sponsorable)
      sponsorship = create(:sponsorship, :private, sponsorable: sponsorable)
      sponsor = sponsorship.sponsor
      rando = create(:user)

      result = GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id], sponsorable_id: sponsorable.id,
        viewer: sponsor)
      assert_instance_of Hash, result
      assert result[sponsor.id]

      assert_equal({ sponsor.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: sponsor,
      ), "viewer should be able to see their own private sponsorship")

      assert_equal({ sponsor.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: sponsorable,
      ), "maintainer should be able to see private sponsorship they are receiving")

      refute GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: nil,
      )[sponsor.id], "anonymous viewer should not be able to see private sponsorships from a user"

      refute GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: rando,
      )[sponsor.id], "unrelated user should not be able to see private sponsorships from another user"
    end

    test "considers viewer permissions for a private sponsorship from an org sponsor" do
      sponsorable = create(:user, :sponsorable)
      sponsorship = create(:sponsorship, :from_org, :private, sponsorable: sponsorable)
      org = sponsorship.sponsor
      org_member, billing_manager = create_pair(:user)
      org.add_member(org_member)
      org.billing.add_manager(billing_manager, actor: org.admin)
      non_member = create(:user)

      assert_equal({ org.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([org.id],
        sponsorable_id: sponsorable.id,
        viewer: org.admin,
      ), "org admin should be able to see private org sponsorships")

      refute GitHubSponsors::Public.sponsor_status_by_sponsor_id([org.id],
        sponsorable_id: sponsorable.id,
        viewer: nil,
      )[org.id], "anonymous viewer should not be able to see private org sponsorships"

      assert_equal({ org.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([org.id],
        sponsorable_id: sponsorable.id,
        viewer: org_member,
      ), "org members should be able to see who their org is sponsoring")

      assert_equal({ org.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([org.id],
        sponsorable_id: sponsorable.id,
        viewer: sponsorable,
      ), "maintainer should be able to see private sponsorship they are receiving")

      assert_equal({ org.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([org.id],
        sponsorable_id: sponsorable.id,
        viewer: billing_manager,
      ), "org billing managers should be able to see who their org is sponsoring")

      refute GitHubSponsors::Public.sponsor_status_by_sponsor_id([org.id],
        sponsorable_id: sponsorable.id,
        viewer: non_member,
      )[org.id], "unrelated user should not be able to see private sponsorships to an org they're not in"
    end

    test "considers viewer permissions for a private sponsorship to an org maintainer" do
      sponsorable = create(:organization, :sponsorable)
      sponsorship = create(:sponsorship, :private, sponsorable: sponsorable)
      sponsor = sponsorship.sponsor
      rando = create(:user)
      org_member, billing_manager = create_pair(:user)
      sponsorable.add_member(org_member)
      sponsorable.billing.add_manager(billing_manager, actor: sponsorable.admin)

      result = GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id], sponsorable_id: sponsorable.id,
        viewer: sponsor)
      assert_instance_of Hash, result
      assert result[sponsor.id]

      assert_equal({ sponsor.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: sponsor,
      ), "viewer should be able to see their own private sponsorship")

      assert_equal({ sponsor.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: sponsorable.admin,
      ), "admin of org being sponsored should be able to see private sponsorship their org is receiving")

      refute GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: nil,
      )[sponsor.id], "anonymous viewer should not be able to see private sponsorships from a user"

      assert_equal({ sponsor.id => true }, GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: org_member,
      ), "member of org being sponsored should be able to see private sponsorship their org is receiving")

      refute GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: rando,
      )[sponsor.id], "unrelated user should not be able to see private sponsorships from another user"

      refute GitHubSponsors::Public.sponsor_status_by_sponsor_id([sponsor.id],
        sponsorable_id: sponsorable.id,
        viewer: billing_manager,
      )[sponsor.id],
        "biling manager of org being sponsored should not be able to see private sponsorships their org receives"
    end
  end
end
