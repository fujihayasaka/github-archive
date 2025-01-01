# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamChangeParentRequestAssociationsTest < GitHub::TestCase
  fixtures do
    @request = create :team_change_parent_request
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  test "requires a parent_team and child_team to be saved" do
    assert @request.valid?
    refute @request.new_record?

    assert @request.child_team.present?
    assert @request.parent_team.present?
    assert @request.requester.present?
  end

  context "child_team" do
    test "destroys the request when destroyed" do
      self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      id = @request.id
      refute_nil TeamChangeParentRequest.find_by(id: id)

      @request.child_team.destroy
      assert_nil TeamChangeParentRequest.find_by(id: id)
    end
  end

  context "parent_team" do
    test "destroys the request when destroyed" do
      self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests

      id = @request.id
      refute_nil TeamChangeParentRequest.find_by(id: id)

      @request.parent_team.destroy
      assert_nil TeamChangeParentRequest.find_by(id: id)
    end
  end
end

class TeamChangeParentRequestValidationsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @child_team = create(:team, organization: @org, privacy: :closed)
    @parent_team = create(:team, organization: @org, privacy: :closed)
    @requester = create :user
  end

  test "can be valid" do
    request = TeamChangeParentRequest.new(
      child_team: @child_team,
      parent_team:  @parent_team,
      requester:  @requester,
    )
    assert request.valid?, "should be valid"
  end

  test "requires a parent team" do
    request = TeamChangeParentRequest.new(child_team: @child_team, requester: @requester)
    refute request.valid?, "should require a parent team"
    assert_includes request.errors.full_messages.join, "Parent team can't be blank"
  end

  test "requires a child team" do
    request = TeamChangeParentRequest.new(parent_team: @parent_team, requester: @requester)
    refute request.valid?, "should require a child team"
    assert_includes request.errors.full_messages.join, "Child team can't be blank"
  end

  test "requires a requester" do
    request = TeamChangeParentRequest.new(parent_team: @parent_team, child_team: @child_team)
    refute request.valid?, "should require a requester"
    assert_includes request.errors.full_messages.join, "Requester can't be blank"
  end

  test "there can only be one pending request per team at a time" do
    params = { parent_team: @parent_team, child_team: @child_team, requester: @requester }
    TeamChangeParentRequest.create(params)
    request = TeamChangeParentRequest.new(params)
    refute request.valid?, "should not allow multiple pending requests"
    assert_includes request.errors.full_messages.join, "Parent team has already been taken"
  end
end

class TeamChangeParentRequestTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @child_team = create(:team, organization: @org, name: "child", privacy: :closed)
    @parent_team = create(:team, organization: @org, name: "parent", privacy: :closed)
    @requester = create(:user, login: "requester")
    @parent_team.add_member(@requester)
    @parent_team.promote_maintainer(@requester)

    @request = create(:team_change_parent_request, :parent,
      child_team: @child_team,
      parent_team: @parent_team,
      requester: @requester
    )

    @actor = create(:user, name: "actor")
    @child_team.add_member(@actor)
    @child_team.promote_maintainer(@actor)
  end

  context ".create_initiated_by_parent!" do
    test "sets the requesting_team to be the parent" do
      parent = create(:team, organization: @org, name: "new-parent", privacy: :closed)

      request = TeamChangeParentRequest.create_initiated_by_parent!(
        parent_team: parent, child_team: @child_team,
        requester: @requester
      )

      assert_predicate request, :persisted?
      assert_predicate request, :parent_request?
      assert_equal parent, request.requesting_team
    end
  end

  context ".create_initiated_by_child!" do
    test "sets the requesting_team to be the child" do
      child = create(:team, organization: @org, name: "new-child", privacy: :closed)
      request = TeamChangeParentRequest.create_initiated_by_child!(
        parent_team: @parent_team, child_team: child,
        requester: @requester
      )

      assert_predicate request, :persisted?
      assert_predicate request, :child_request?
      assert_equal child, request.requesting_team
    end
  end

  context "#approve" do
    test "marks the request as approved" do
      @request.approve(actor: @actor)

      assert_predicate @request, :approved?
    end

    test "marks the request as approved by the passed in actor" do
      @request.approve(actor: @actor)

      assert_equal @actor, @request.approved_by
    end

    test "moves the child team to the parent team" do
      refute_equal @request.parent_team, @request.child_team.parent_team

      @request.approve(actor: @actor)

      assert_equal @request.parent_team, @request.child_team.reload.parent_team
    end

    test "raises an error when the request has already been approved" do
      @request.approve(actor: @actor)
      assert_predicate @request, :approved?

      assert_raises TeamChangeParentRequest::AlreadyApprovedError do
        @request.approve(actor: @actor)
      end
    end

    test "does not allow requests to be created between teams that are not in the same org" do
      other_org = create(:organization, login: "other-org")
      other_child_team = create :team, organization: other_org, name: "other-child-team", privacy: :closed
      other_approver = create(:user, login: "otherapprover")
      other_child_team.add_member(other_approver)
      other_child_team.promote_maintainer(other_approver)

      request = TeamChangeParentRequest.new(
        parent_team: @parent_team,
        child_team: other_child_team,
        requester: @requester,
      )

      refute request.valid?
      assert_includes request.errors.messages[:organization], "parent team and child team must be in the same organization"
      refute_equal other_child_team.parent_team, @parent_team
    end
  end

  context "#approved_by" do
    test "returns the actor that approved the request" do
      @request.approve(actor: @actor)

      assert_equal @actor, @request.approved_by
    end
  end

  context "cancel" do
    test "deletes the request, if pending" do
      assert_difference("TeamChangeParentRequest.count", -1) do
        @request.cancel(actor: @actor)
      end
    end

    test "raises and does not delete if request has already been approved" do
      @request.approve(actor: @actor)

      assert_no_difference("TeamChangeParentRequest.count") do
        assert_raises TeamChangeParentRequest::AlreadyApprovedError do
          @request.cancel(actor: @actor)
        end
      end
    end

    test "instruments the expected payload" do
      events     = subscribe("team.cancel_child_team_request")
      @request.cancel(actor: @actor)

      event            = events.pop
      expected_payload = {
        ldap_mapped:  false,
        note:         "Team #{@parent_team}",
        team:         "#{@parent_team}",
        team_id:      @parent_team.id,
        org:          @parent_team.organization.login,
        org_id:       @parent_team.organization.id,
        actor:        @actor.login,
        actor_id:     @actor.id,
        requester:    @requester.login,
        requester_id: @requester.id,
      }

      refute_nil event
      assert_equal "team.cancel_child_team_request", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context ".involving" do
    test "includes requests where the given team is a parent" do
      requests = TeamChangeParentRequest.involving(@parent_team)

      assert_same_elements [@parent_team], requests.map(&:parent_team)
    end

    test "includes requests where the given team is a child" do
      requests = TeamChangeParentRequest.involving(@child_team)

      assert_same_elements [@child_team], requests.map(&:child_team)
    end
  end

  context ".pending" do
    test "includes only requests that have not yet been approved" do
      approved_request = create(:team_change_parent_request,
        child_team: @child_team,
        parent_team: create(:team, organization: @org, name: "other-team", privacy: :closed),
        requester: @requester,
      )
      approved_request.approve(actor: @actor)

      assert_same_elements TeamChangeParentRequest.pending, [@request]
    end

  end

  context "inbound_pending_requests_non_null_*" do
    test "for parent initiated" do
      child = create(:team, organization: @org, privacy: :closed)

      good_request = TeamChangeParentRequest.create_initiated_by_parent!(
        child_team: child,
        parent_team: create(:team, organization: @org, privacy: :closed),
        requester: @requester
      )

      bad_request = TeamChangeParentRequest.create_initiated_by_parent!(
        child_team: child,
        parent_team: create(:team, organization: @org, privacy: :closed),
        requester: @requester
      )
      bad_request.parent_team.delete

      assert_equal 1, TeamChangeParentRequest.inbound_pending_requests_non_null_parent_initiated(child).length
      assert_equal good_request, TeamChangeParentRequest.inbound_pending_requests_non_null_parent_initiated(child).first
    end

    test "for child initiated" do
      parent = create(:team, organization: @org, privacy: :closed)

      good_request = TeamChangeParentRequest.create_initiated_by_child!(
        child_team: create(:team, organization: @org, privacy: :closed),
        parent_team: parent,
        requester: @requester
      )

      bad_request = TeamChangeParentRequest.create_initiated_by_child!(
        child_team: create(:team, organization: @org, privacy: :closed),
        parent_team: parent,
        requester: @requester
      )
      bad_request.child_team.delete

      results = TeamChangeParentRequest.inbound_pending_requests_non_null_child_initiated(parent)
      assert_equal 1, results.length
      assert_equal good_request, results.first
    end
  end

  context ".identical_to" do
    context "a request id is passed in" do
      test "includes all identical TeamChangeParentRequests" do
        identical_request = TeamChangeParentRequest.create_initiated_by_child!(
          child_team: @child_team,
          parent_team: @parent_team,
          requester: @actor,
        )

        identical_requests = TeamChangeParentRequest.identical_to(@parent_team.id, @child_team.id, @request.id)

        assert_includes identical_requests, identical_request
      end

      test "does not include the request whose id was passed in" do
        identical_request = TeamChangeParentRequest.create_initiated_by_child!(
          child_team: @child_team,
          parent_team: @parent_team,
          requester: @actor,
        )

        identical_requests = TeamChangeParentRequest.identical_to(@parent_team.id, @child_team.id, @request.id)

        refute_includes identical_requests, @request
      end

      test "excludes non-identical TeamChangeParentRequests" do
        non_identical_request = TeamChangeParentRequest.create_initiated_by_parent!(
          child_team: @parent_team,
          parent_team: @child_team,
          requester: @requester,
        )

        identical_requests = TeamChangeParentRequest.identical_to(@parent_team.id, @child_team.id, @request.id)

        refute_includes identical_requests, non_identical_request
      end
    end

    context "a request id is NOT passed in" do
      test "includes identical TeamChangeParentRequests" do
        identical_request = TeamChangeParentRequest.create_initiated_by_child!(
          child_team: @child_team,
          parent_team: @parent_team,
          requester: @actor,
        )

        identical_requests = TeamChangeParentRequest.identical_to(@parent_team.id, @child_team.id)

        assert_includes identical_requests, @request
        assert_includes identical_requests, identical_request
      end

      test "excludes non-identical TeamChangeParentRequests" do
        identical_request = TeamChangeParentRequest.create_initiated_by_child!(
          child_team: @child_team,
          parent_team: @parent_team,
          requester: @actor,
        )

        identical_requests = TeamChangeParentRequest.identical_to(@parent_team.id, @child_team.id)

        refute_includes identical_requests, @non_identical_requst
      end
    end
  end

  context ".circular_to" do
    test "includes all pending TeamChangeParentRequests with circular relationship to the original request" do
      @request.approve(actor: @actor)

      team = create(:team, organization: @org, name: "team", privacy: :closed)
      team_maintainer = create(:user, name: "team-maintainer")
      team.add_member(team_maintainer)
      team.promote_maintainer(team_maintainer)

      parent_request = TeamChangeParentRequest.create_initiated_by_child!(
        child_team: @parent_team,
        parent_team: team,
        requester: @requester,
      )

      child_request = TeamChangeParentRequest.create_initiated_by_parent!(
        child_team: team,
        parent_team: @child_team,
        requester: @actor,
      )

      @child_team.reload
      @parent_team.reload

      child_circular_reqs = TeamChangeParentRequest.circular_to(child_request)
      parent_circular_reqs = TeamChangeParentRequest.circular_to(parent_request)

      assert_equal [parent_request], child_circular_reqs
      assert_equal [child_request], parent_circular_reqs
    end

    test "does not include the original request" do
      @request.approve(actor: @actor)

      team = create(:team, organization: @org, name: "team", privacy: :closed)
      team_maintainer = create(:user, name: "team-maintainer")
      team.add_member(team_maintainer)
      team.promote_maintainer(team_maintainer)

      new_request = TeamChangeParentRequest.create_initiated_by_child!(
        child_team: @parent_team,
        parent_team: team,
        requester: @requester,
      )

      @parent_team.reload

      circular_requests = TeamChangeParentRequest.circular_to(new_request)

      refute_includes circular_requests, new_request
    end

    test "excludes requests that are not circular to the original request" do
      team1 = create(:team, organization: @org, name: "team1", privacy: :closed)
      team1.add_member(@actor)
      team1.promote_maintainer(@actor)

      team2 = create(:team, organization: @org, name: "team2", privacy: :closed)
      team2.add_member(@requester)
      team2.promote_maintainer(@requester)

      non_circular_request = TeamChangeParentRequest.create_initiated_by_child!(
        child_team: team1,
        parent_team: team2,
        requester: @actor,
      )

      circular_requests = TeamChangeParentRequest.circular_to(@request)

      refute_includes circular_requests, non_circular_request
    end
  end

  context "#pending?" do
    test "returns false when the request is approved" do
      @request.approve(actor: @actor)

      refute_predicate @request, :pending?
    end

    test "returns true when the request is pending" do
      assert_predicate @request, :pending?
    end
  end

  context "#approved?" do
    test "returns false when the request is pending" do
      refute_predicate @request, :approved?
    end

    test "returns true when the request is approved" do
      @request.approve(actor: @actor)

      assert_predicate @request, :approved?
    end
  end

  context "#requesting_team" do
    test "returns the child team by default" do
      other_child_team = create(:team, organization: @org, name: "other-child-team", privacy: :closed)

      request = create(:team_change_parent_request,
        child_team: other_child_team,
        parent_team: @parent_team,
        requester: @requester,
      )

      assert_equal other_child_team, request.requesting_team
    end

    test "returns the parent team when it is requesting the change" do
      request = create(:team_change_parent_request, :parent, parent_team: @parent_team)

      assert_equal @parent_team, request.requesting_team
    end
  end

  context "#requested_team" do
    test "returns the child when the parent initiates the request" do
      child = create(:team, organization: @org, privacy: :closed)
      parent = create(:team, organization: @org, privacy: :closed)
      request = TeamChangeParentRequest.create_initiated_by_parent!(
        child_team: child, parent_team: parent,
        requester: @requester
      )

      assert_equal child, request.requested_team
    end

    test "returns the parent when the child initiates the request" do
      child = create(:team, organization: @org, privacy: :closed)
      parent = create(:team, organization: @org, privacy: :closed)
      request = TeamChangeParentRequest.create_initiated_by_child!(
        child_team: child, parent_team: parent,
        requester: @requester
      )
      assert_equal parent, request.requested_team
    end
  end

  context "#child_request?" do
    test "returns false when the request was initiated from a parent team" do
      request = create(:team_change_parent_request, :parent)

      refute_predicate request, :child_request?
    end

    test "returns true when the request was initiated from a child team" do
      request = create(:team_change_parent_request, :child)

      assert_predicate request, :child_request?
    end
  end

  context "#parent_request?" do
    test "returns false when the request was initiated from a child team" do
      request = create(:team_change_parent_request, :child)

      refute_predicate request, :parent_request?
    end

    test "returns true when the request was initiated from a parent team" do
      request = create(:team_change_parent_request, :parent)

      assert_predicate request, :parent_request?
    end
  end

  context "#after_create" do
    test "instruments the expected payload" do
      child_team = create :team, organization: @org
      parent_team = create :team, organization: @org

      events = subscribe("team.team_relationship_request")
      request = create(:team_change_parent_request, requester: @requester)

      team = request.requesting_team

      event            = events.pop
      expected_payload = {
        ldap_mapped: false,
        note: "Team #{team}",
        team: "#{team}",
        team_id: team.id,
        org: team.organization.login,
        org_id: team.organization.id,
        requester: @requester.login,
        requester_id: @requester.id,
      }

      refute_nil event
      assert_equal "team.team_relationship_request", event.name
      assert_equal expected_payload, event.payload
    end

    test "triggers sending a mail after a parent request is created by a parent" do
      admin_user = create :user
      child_team = create(:team, organization: @org, privacy: :closed)
      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team.add_member(admin_user)
      child_team.promote_maintainer(admin_user)

      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          TeamChangeParentRequest.create_initiated_by_parent!(
            child_team: child_team,
            parent_team: parent_team,
            requester: @requester,
          )
        end
      end
    end

    test "triggers sending a mail after a parent request is created by a child" do
      admin_user = create :user
      child_team = create(:team, organization: @org, privacy: :closed)
      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team.add_member(admin_user)
      child_team.promote_maintainer(admin_user)

      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
          TeamChangeParentRequest.create_initiated_by_child!(
            child_team: child_team,
            parent_team: parent_team,
            requester: @requester,
          )
        end
      end
    end
  end

end
