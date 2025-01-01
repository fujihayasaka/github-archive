# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionAnsweredDiscussionTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @discussion = create(:discussion_with_answer, :closed)
    @answer = create(:discussion_comment, user: @user, discussion: @discussion)
    @discussion.update(chosen_comment_id: @answer.id)
    @discussion_event = create(:discussion_event, event_type: :answer_marked,
      discussion: @discussion, comment: @answer)
  end

  setup do
    @contribution = Contribution::AnsweredDiscussion.new(
      user: @user,
      subject: @discussion_event,
    )
  end

  context "#occurred_at" do
    test "returns the discussion event's creation time" do
      assert_equal @discussion_event.created_at, @contribution.occurred_at
    end
  end

  [:repository, :discussion, :comment].each do |method|
    context "##{method}" do
      test "returns the discussion event's #{method}" do
        assert_equal @discussion_event.send(method), @contribution.send(method)
      end
    end
  end

  [:title, :number, :comment_count, :state, :state_reason].each do |method|
    context "##{method}" do
      test "returns the discussion #{method}" do
        assert_equal @discussion.send(method), @contribution.send(method)
      end
    end
  end

  context "#associated_subject" do
    test "returns the repository of the discussion event" do
      assert_equal @discussion_event.repository, @contribution.associated_subject
    end
  end

  context "#organization_id" do
    test "returns the organization ID of the repository of the discussion event" do
      org_id = 123
      repo = stub(organization_id: org_id)
      event = stub(repository: repo)
      contribution = Contribution::AnsweredDiscussion.new(user: @user, subject: event)
      assert_equal org_id, contribution.organization_id
    end
  end

  context "#discussion_event" do
    test "returns the discussion event" do
      assert_equal @discussion_event, @contribution.discussion_event
    end
  end

  context "#repository_id" do
    test "returns the id of the discussion event's repository" do
      assert_equal @discussion_event.repository_id, @contribution.repository_id
    end
  end

  def subjects_for(
    user,
    date_range: Date.yesterday..Date.tomorrow,
    organization_id: nil,
    excluded_organization_ids: []
  )
    contribution_class = Contribution::AnsweredDiscussion
    contribution_class.subjects_for(
      user, date_range: date_range, organization_id: organization_id,
      excluded_organization_ids: excluded_organization_ids
    )
  end

  context "::subjects_for" do
    test "includes the user's discussion events for answered discussions" do
      private_repo = create :private_repository, owner: @user, has_discussions: true
      private_discussion = create :discussion, repository: private_repo
      private_answer = create :discussion_comment, discussion: private_discussion, user: @user
      private_discussion.update(chosen_comment_id: private_answer.id)
      private_event = create(:discussion_event, discussion: private_discussion,
        event_type: :answer_marked, comment: private_answer)

      subjects = subjects_for(@user)
      subjects.each do |subject|
        assert_kind_of DiscussionEvent, subject
      end
      assert_same_elements [@discussion_event, private_event], subjects
    end

    test "allows filtering discussion events by organization" do
      org_a, org_b = create_pair(:organization, public_members: [@user]).each do |org|
        repo = create :private_repository, owner: org, has_discussions: true
        discussion = create :discussion, repository: repo
        answer = create :discussion_comment, discussion: discussion, user: @user
        answer.mark_as_answer
      end

      subjects = subjects_for(@user, organization_id: org_a.id)

      assert_same_elements org_a.repositories.first.discussions.first.events.answer_marked, subjects
    end

    test "excludes contributions in orgs specified by excluded_organization_ids" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user]) do |org|
        repo = create :private_repository, owner: org, has_discussions: true
        discussion = create :discussion, repository: repo
        answer = create :discussion_comment, discussion: discussion, user: @user
        answer.mark_as_answer
      end

      subjects = subjects_for(@user, excluded_organization_ids: [excluded_org.id])

      assert_same_elements \
        [@discussion_event, other_org.repositories.first.discussions.first.events.answer_marked.first],
        subjects
    end

    test "excludes contributions when the repository has been deleted" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user]) do |org|
        repo = create :private_repository, owner: org, has_discussions: true
        discussion = create :discussion, repository: repo
        answer = create :discussion_comment, discussion: discussion, user: @user
        answer.mark_as_answer
      end

      other_org.repositories.first.destroy

      subjects = subjects_for(@user, excluded_organization_ids: [excluded_org.id])

      assert_same_elements [@discussion_event], subjects
    end

    test "only returns discussion events created in the given time range with buffer" do
      travel_to Time.zone.local(2001, 9, 4, 00, 00, 00) do
        event = create(:discussion_event, event_type: :answer_marked, discussion: @discussion, comment: @answer)
        subjects = subjects_for(@user, date_range: 3.days.ago.to_date..2.days.ago.to_date)

        assert_empty subjects
      end
    end

    test "only returns discussion events for comments created by the specified user" do
      subjects = subjects_for(create(:user))
      assert_empty subjects
    end

    test "limits the number of discussion events to avoid performance bottlenecks" do
      subjects = subjects_for(@user)
      refute_empty subjects

      Contribution.stub_const(:DEFAULT_COUNT_LIMIT, 0) do
        subjects = subjects_for(@user)
        assert_empty subjects
      end
    end
  end
end
