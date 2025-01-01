# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionJoinedOrganizationTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)

    @org.add_member(@user)
    @ability = Ability.where(actor_id: @user, actor_type: "User", priority: Ability.priorities[:direct]).last
  end

  setup do
    @contribution = Contribution::JoinedOrganization.new(
      user: @user,
      subject: [@org, @ability.created_at],
    )
  end

  context "#organization_id" do
    test "returns the ID of the organization that was joined" do
      assert_equal @org.id, @contribution.organization_id
    end
  end

  context "#occurred_at" do
    test "returns ability creation time" do
      assert_equal @ability.created_at, @contribution.occurred_at
    end
  end

  context "#login" do
    test "returns login of given organization" do
      assert_equal @org.login, @contribution.login
    end
  end

  context "#associated_subject" do
    test "returns the organization" do
      assert_equal @org, @contribution.organization
    end
  end

  def subjects_for(user, date_range: Date.yesterday..Date.tomorrow, organization_id: nil, excluded_organization_ids: [])
    Contribution::JoinedOrganization.subjects_for(user, date_range: date_range, organization_id: organization_id, excluded_organization_ids: excluded_organization_ids)
  end

  context "::subjects_for" do
    test "returns an empty array when user has never joined an organization" do
      user = create(:user)

      assert_empty subjects_for(user)
    end

    test "includes abilities representing a user's public org memberships" do
      @org.add_member @user
      @org.publicize_member @user

      subjects = subjects_for(@user)

      assert_equal 1, subjects.count
      org, created_at = subjects.first
      assert_equal @org, org
      assert_kind_of Time, created_at
    end

    test "ignores memberships to org the user no longer belongs to" do
      @org.add_member @user
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) { @org.remove_member @user }

      assert_empty subjects_for(@user)
    end

    test "ignores memberships to orgs that have been deleted" do
      @org.add_member @user
      @org.destroy

      assert_empty subjects_for(@user)
    end

    test "includes non-public memberships" do
      @org.add_member @user
      @org.conceal_member @user

      subjects = subjects_for(@user)

      assert_equal 1, subjects.count
      org, created_at = subjects.first
      assert_equal @org, org
      assert_kind_of Time, created_at
    end

    test "allows restriction by organization" do
      org_a, org_b = create_pair(:organization, public_members: [@user])

      subjects = subjects_for(@user, organization_id: org_a.id)

      assert_equal [org_a], subjects.map(&:first)
    end

    test "excludes organizations from the excluded_organization_ids list" do
      @org.add_member @user
      @org.conceal_member @user

      subjects = subjects_for(@user, excluded_organization_ids: [@org.id])

      assert_empty subjects
    end
  end
end
