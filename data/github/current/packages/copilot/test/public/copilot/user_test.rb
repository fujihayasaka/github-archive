# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUserTest < GitHub::TestCase
  context "#copilot_for_business_enabled?" do
    test "defaults to false" do
      user = create(:user)
      refute Copilot::User.new(user).copilot_for_business_enabled?
    end

    test "returns true if the user has a CFB seat" do
      user = create(:user)
      business = create(:business)
      organization = create(:organization, business: business)
      organization.add_member user
      create(:copilot_seat, assigned_user: user, organization: organization)
      assert Copilot::User.new(user).copilot_for_business_enabled?
    end
  end

  context "#codespaces_demo_usage_allowed?" do
    test "returns true for codespaces created from the demo repository" do
      repository = create(:repository)
      GitHub.flipper[:codespaces_copilot_demo_repository].enable(repository)

      user = create(:user)
      codespace = create(:codespace, owner: user, repository:)

      assert Copilot::User.new(user).codespaces_demo_usage_allowed?(codespace)
    end

    test "returns false for codespaces created from other repositories" do
      repository = create(:repository)
      GitHub.flipper[:codespaces_copilot_demo_repository].disable(repository)

      user = create(:user)
      codespace = create(:codespace, owner: user, repository:)

      refute Copilot::User.new(user).codespaces_demo_usage_allowed?(codespace)
    end
  end

  context "#codespaces_demo_request_allowed?" do
    test "returns false if there's no oauth_access" do
      user = create(:user)
      user.oauth_access = nil

      refute Copilot::User.new(user).codespaces_demo_request_allowed?
    end

    test "returns false for an OAuth token" do
      user = create(:user)
      user.oauth_access = make_oauth(user)

      refute Copilot::User.new(user).codespaces_demo_request_allowed?
    end

    test "returns false for a PAT" do
      user = create(:user)
      user.oauth_access = make_pat(user, scopes: [:repo])

      refute Copilot::User.new(user).codespaces_demo_request_allowed?
    end

    test "returns false for some other integration's installation" do
      user = create(:user)
      repo = create(:repository, owner: user)

      installation = make_integration_installation(repository: repo)
      grant = installation.integration.grant(user)

      new_access, error_response = installation.integration.grant_scoped_access_from(grant, user)
      assert_nil error_response

      user.oauth_access = new_access

      refute Copilot::User.new(user).codespaces_demo_request_allowed?
    end
  end

  context "#has_enterprise_seat?" do
    context "emu standalone business" do
      test "returns true when the user has a seat within a standalone business" do
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        seat_assignment.convert_to_seats

        copilot_user = Copilot::User.new(seat_assignment.seats.first.assigned_user)

        assert copilot_user.has_enterprise_seat?
      end

      test "returns false when user has no seat within a standalone business" do
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        seat_assignment.convert_to_seats

        copilot_user = Copilot::User.new(create(:user, business: seat_assignment.owner))

        refute copilot_user.has_enterprise_seat?
      end

      test "returns true when user is a guest collaborator" do
        seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
        seat_assignment.convert_to_seats

        copilot_user = Copilot::User.new(seat_assignment.seats.first.assigned_user)
        copilot_user.user_object.stubs(:guest_collaborator?).returns(true)

        assert copilot_user.has_enterprise_seat?
      end
    end if TestEnv.test_with_all_emus?

    context "non-emu standalone business" do
      test "returns true when user has a seat" do
        biz = create(:business)
        biz.update(seats_plan_type: :basic)

        team = create(:enterprise_team, business: biz)
        user = create(:user)
        biz.add_user_accounts([user.id], business_roles_bitfield: 0)
        team.enterprise_team_memberships.create!(user_id: user.id)

        assignment = Copilot::SeatAssignment.new(
          owner_id: team.business_id,
          owner_type: "Business",
          assignable_type: "EnterpriseTeam",
          assignable_id: team.id,
          assigning_user: team.business.owners.first,
        )
        assignment.save!
        assignment.convert_to_seats

        copilot_user = Copilot::User.new(user)

        assert copilot_user.has_enterprise_seat?
      end

      test "returns false when a user has no seat" do
        biz = create(:business)
        biz.update(seats_plan_type: :basic)

        team = create(:enterprise_team, business: biz)
        user = create(:user)
        biz.add_user_accounts([user.id], business_roles_bitfield: 0)
        team.enterprise_team_memberships.create!(user_id: user.id)

        assignment = Copilot::SeatAssignment.new(
          owner_id: team.business_id,
          owner_type: "Business",
          assignable_type: "EnterpriseTeam",
          assignable_id: team.id,
          assigning_user: team.business.owners.first,
        )
        assignment.save!
        assignment.convert_to_seats

        other_user = create(:user, business: biz)
        biz.add_user_accounts([other_user.id], business_roles_bitfield: 0)

        copilot_user = Copilot::User.new(other_user)

        refute copilot_user.has_enterprise_seat?
      end
    end unless TestEnv.test_with_all_emus?

    context "for full enterprises" do
      test "returns true when user has seat in organization with parent enterprise" do
        org = create(:copilot_enterprise_enabled_organization)
        user = org.admins.first

        org.add_member(user)

        seat_assignment = create(:copilot_seat_assignment, assignable: user, owner: org, organization: org)
        seat_assignment.convert_to_seats

        assert Copilot::User.new(user).has_enterprise_seat?
      end

      test "returns false when user has no seat in organization with parent enterprise" do
        org = create(:copilot_enterprise_enabled_organization)
        user = org.admins.first
        other_user = create(:user)

        org.add_member(user)
        org.add_member(other_user)

        seat_assignment = create(:copilot_seat_assignment, assignable: user, owner: org, organization: org)
        seat_assignment.convert_to_seats

        refute Copilot::User.new(other_user).has_enterprise_seat?
      end
    end
  end
end if GitHub.copilot_enabled?
