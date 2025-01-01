# typed: true
# frozen_string_literal: true

require "test_helper"

class ContributionJoinedGitHubTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  setup do
    @contribution = Contribution::JoinedGitHub.new(user: @user)
  end

  test "occurred_at returns when the user was created" do
    assert_equal @user.created_at, @contribution.occurred_at
  end

  context "#pretty_date" do
    test "returns the occurred_at as a pretty formatted date" do
      @contribution.stubs(:occurred_at).returns(Time.local(2014, 3, 12))
      assert_equal "March 12, 2014", @contribution.pretty_date
    end
  end

  context "#associated_subject" do
    test "does not have an associated subject" do
      assert_equal @user, @contribution.associated_subject
    end
  end

  def subjects_for(user, date_range:, organization_id: nil)
    Contribution::JoinedGitHub.subjects_for(user, date_range: date_range, organization_id: organization_id)
  end

  context "::subjects_for" do
    test "returns a the user when user joined in the given date range" do
      from = @user.created_at - 1.day
      to = @user.created_at + 1.minute

      assert_equal [@user], subjects_for(@user, date_range: from.to_date..to.to_date)
    end

    test "returns an empty array when user did not join in the given date range" do
      from = @user.created_at - 2.days
      to = @user.created_at - 1.day

      assert_empty subjects_for(@user, date_range: from.to_date..to.to_date)
    end
  end

  context "::first_subject_for" do
    test "returns the user" do
      assert_equal @user, Contribution::JoinedGitHub.first_subject_for(@user)
    end
  end
end
