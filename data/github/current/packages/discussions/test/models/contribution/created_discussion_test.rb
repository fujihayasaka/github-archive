# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionCreatedDiscussionTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @discussion = create(:discussion, :closed, user: @user)
  end

  setup do
    @contribution = Contribution::CreatedDiscussion.new(
      user: @user,
      subject: @discussion,
    )
  end

  context "#occurred_at" do
    test "returns the discussion's creation time" do
      assert_equal @discussion.created_at, @contribution.occurred_at
    end
  end

  [:repository, :title, :number, :comment_count].each do |method|
    context "##{method}" do
      test "returns the discussion #{method}" do
        assert_equal @discussion.send(method), @contribution.send(method)
      end
    end
  end

  context "#associated_subject" do
    test "returns the repository of the discussion" do
      assert_equal @discussion.repository, @contribution.associated_subject
    end
  end

  context "#organization_id" do
    test "returns the organization ID of the repository of the discussion" do
      org_id = 123
      repo = stub(organization_id: org_id)
      discussion = stub(repository: repo)
      contribution = Contribution::CreatedDiscussion.new(user: @user, subject: discussion)
      assert_equal org_id, contribution.organization_id
    end
  end

  context "#discussion" do
    test "returns the discussion" do
      assert_equal @discussion, @contribution.discussion
    end
  end

  context "#repository_id" do
    test "returns the id of the discussion's repository" do
      assert_equal @discussion.repository_id, @contribution.repository_id
    end
  end

  def subjects_for(
    user,
    date_range: Date.yesterday..Date.tomorrow,
    organization_id: nil,
    excluded_organization_ids: [],
    lightweight: false
  )
    contribution_class = Contribution::CreatedDiscussion
    contribution_class.subjects_for(
      user, date_range: date_range, organization_id: organization_id,
      excluded_organization_ids: excluded_organization_ids,
      lightweight: lightweight,
    )
  end

  context "::subjects_for" do
    test "includes the user's discussions" do
      private_repo = create :private_repository, owner: @user, has_discussions: true
      private_discussion = create :discussion, user: @user, repository: private_repo

      subjects = subjects_for(@user)
      subjects.each do |subject|
        assert_kind_of Discussion, subject
      end
      assert_same_elements [@discussion, private_discussion], subjects
    end

    test "allows filtering discussions by organization" do
      org_a, org_b = create_pair(:organization, public_members: [@user]).each do |org|
        repo = create :private_repository, owner: org, has_discussions: true
        create :discussion, user: @user, repository: repo
      end

      subjects = subjects_for(@user, organization_id: org_a.id)

      assert_same_elements org_a.repositories.first.discussions, subjects
    end

    test "excludes contributions in orgs specified by excluded_organization_ids" do
      excluded_org, other_org = create_pair(:organization, public_members: [@user]) do |org|
        repo = create :private_repository, owner: org, has_discussions: true
        create :discussion, user: @user, repository: repo
      end

      subjects = subjects_for(@user, excluded_organization_ids: [excluded_org.id])

      assert_same_elements \
        [@discussion, other_org.repositories.first.discussions.first],
        subjects
    end

    test "only returns discussions created in the given time range with buffer" do
      travel_to Time.zone.local(2001, 9, 4, 00, 00, 00) do
        create(:discussion, user: @user)
        subjects = subjects_for(@user, date_range: 3.days.ago.to_date..2.days.ago.to_date)

        assert_empty subjects
      end
    end

    test "only returns discussions created by the specified user" do
      subjects = subjects_for(create(:user))
      assert_empty subjects
    end

    test "limits the number of discussions to avoid performance bottlenecks" do
      subjects = subjects_for(@user)
      refute_empty subjects

      Contribution.stub_const(:DEFAULT_COUNT_LIMIT, 0) do
        subjects = subjects_for(@user)
        assert_empty subjects
      end
    end

    test "works for discussions that no longer have repositories" do
      user = create(:verified_user)
      org = create(:organization)
      repo = create(:repository, owner: org, has_discussions: true)
      discussion = create(:discussion, repository: repo, user: user)
      discussion.repository.destroy
      discussion.reload

      subjects = subjects_for(user, excluded_organization_ids: [org.id])
      assert_same_elements [discussion], subjects
    end

    test "lightweight subject includes state data" do
      subjects = subjects_for(@user, lightweight: true)
      assert_equal 1, subjects.size
      subject = subjects.first

      assert_equal @discussion.state, subject.state
      assert_equal @discussion.state_reason, subject.state_reason
    end
  end
end
