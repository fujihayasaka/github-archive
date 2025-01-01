# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamMembershipRequestAssociationsTest < GitHub::TestCase
  fixtures do
    @request = create :team_membership_request
  end

  test "belongs_to save to the database" do
    assert @request.valid?
    refute @request.new_record?

    assert @request.team.present?
    assert @request.requester.present?
  end

  context "team" do
    test "destroys the membership request when destroyed" do
      self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      GitHub.context.push(actor_id: (create :user).id)
      id = @request.id
      refute_nil TeamMembershipRequest.find_by(id: id)

      @request.team.destroy
      assert_nil TeamMembershipRequest.find_by(id: id)
    end
  end

  context "requester" do
    test "destroys the membership request when destroyed" do
      id = @request.id
      refute_nil TeamMembershipRequest.find_by(id: id)

      @request.requester.destroy
      assert_nil TeamMembershipRequest.find_by(id: id)
    end
  end
end

class TeamMembershipRequestValidationsTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @team = create :team, organization: @org

    @org_admin  = create(:user)
    @org_member = create(:user)
    @non_member = create(:user)

    @org.add_member @org_admin,  action: :admin
    @org.add_member @org_member, action: :read
  end

  test "can be valid" do
    request = TeamMembershipRequest.new(
      team: @team,
      requester: @org_member,
    )
    assert request.valid?, "should be valid"
  end

  test "requires a team" do
    request = TeamMembershipRequest.new(requester: @org_member)
    refute request.valid?, "should require a team"
  end

  test "requires a requester" do
    request = TeamMembershipRequest.new(team: @team)
    refute request.valid?, "should require a requester"
  end

  test "requester can only have one pending request per team at a time" do
    params = { team: @team, requester: @org_member }
    TeamMembershipRequest.create(params) # Create a membership request
    request = TeamMembershipRequest.new(params) # Create a second request
    refute request.valid?, "should not allow multiple pending requests"
  end
end

class TeamMembershipRequestTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @team = create :team, organization: @org

    @org_admin = create(:user, login: "org-admin")
    @team_maintainer = create(:user, login: "team-maintainer")
    @requester  = create(:user, login: "requester")

    @org.add_member @org_admin,  action: :admin
    @org.add_member @team_maintainer, action: :read
    @org.add_member @requester, action: :read
    @team.add_member @team_maintainer
    @team.promote_maintainer @team_maintainer
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  context "approved?" do
    test "is false before the request has been approved" do
      membership_request = @team.request_membership(@requester)

      refute membership_request.approved?
    end

    test "is true after the request has been approved" do
      membership_request = @team.request_membership(@requester)
      membership_request.approve(actor: @org_admin)

      assert membership_request.approved?
    end
  end

  context "approve" do
    test "adds the requester to the team" do
      refute @team.member? @requester

      membership_request = @team.request_membership(@requester)
      membership_request.approve(actor: @org_admin)

      assert @team.member? @requester
      assert membership_request.approved?
    end

    test "can only be performed once" do
      membership_request = @team.request_membership(@requester)
      membership_request.approve(actor: @org_admin)

      assert_raises TeamMembershipRequest::AlreadyApprovedError do
        membership_request.approve(actor: @org_admin)
      end
    end

    test "raises error when the requester cannot be added to the team" do
      membership_request = @team.request_membership(@requester)
      Team.any_instance.stubs(:add_member).returns(Team::AddMemberStatus::BLOCKED)

      assert_raises RuntimeError do
        membership_request.approve(actor: @org_admin)
      end
    end

    test "instruments the expected payload" do
      events = subscribe("team.approve_team_membership_request")
      membership_request = @team.request_membership(@requester)
      membership_request.approve(actor: @org_admin)

      event            = events.pop
      expected_payload = {
        ldap_mapped: false,
        note: "Team #{@team}",
        team: "#{@team}",
        team_id: @team.id,
        org: @team.organization.login,
        org_id: @team.organization.id,
        actor: @org_admin.login,
        actor_id: @org_admin.id,
        requester: @requester.login,
        requester_id: @requester.id,
      }

      refute_nil event
      assert_equal "team.approve_team_membership_request", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "cancel" do
    test "deletes the request, if pending" do
      membership_request = @team.request_membership(@requester)
      assert_difference("TeamMembershipRequest.count", -1) do
        membership_request.cancel(actor: @team_maintainer)
      end
    end

    test "raises and does not delete if request has already been approved" do
      membership_request = @team.request_membership(@requester)
      membership_request.approve(actor: @org_admin)

      assert_no_difference("TeamMembershipRequest.count") do
        assert_raises TeamMembershipRequest::AlreadyApprovedError do
          membership_request.cancel(actor: @team_maintainer)
        end
      end
    end

    test "instruments the expected payload" do
      events = subscribe("team.cancel_team_membership_request")
      membership_request = @team.request_membership(@requester)
      membership_request.cancel(actor: @requester)

      event            = events.pop
      expected_payload = {
        ldap_mapped: false,
        note: "Team #{@team}",
        team: "#{@team}",
        team_id: @team.id,
        org: @team.organization.login,
        org_id: @team.organization.id,
        actor: @requester.login,
        actor_id: @requester.id,
        requester: @requester.login,
        requester_id: @requester.id,
      }

      refute_nil event
      assert_equal "team.cancel_team_membership_request", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#after_create" do
    test "instruments the expected payload" do
      events = subscribe("team.team_membership_request")
      @team.request_membership(@requester)

      event            = events.pop
      expected_payload = {
        ldap_mapped: false,
        note: "Team #{@team}",
        team: "#{@team}",
        team_id: @team.id,
        org: @team.organization.login,
        org_id: @team.organization.id,
        requester: @requester.login,
        requester_id: @requester.id,
      }

      refute_nil event
      assert_equal "team.team_membership_request", event.name
      assert_equal expected_payload, event.payload
    end
  end

  test "triggers sending a mail after a request is created" do
    org = create(:organization)
    team = create :team, organization: org

    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
        create :team_membership_request, team: team
      end
    end
  end
end
