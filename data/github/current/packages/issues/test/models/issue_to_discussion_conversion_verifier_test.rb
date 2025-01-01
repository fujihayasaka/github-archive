# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueToDiscussionConversionVerifierTest < GitHub::TestCase
  fixtures do
    owner = create(:user)
    @repo = create(:repository, owner: owner, has_discussions: true)
    @issue = create(:issue, repository: @repo)
  end

  context "#verify!" do
    test "does not raise if comments counts match" do
      create(:issue_comment, issue: @issue)
      discussion = create_converted_discussion
      create(:discussion_comment, discussion: discussion)

      verify!(discussion)
    end

    test "includes spammy issue comments in verficiation" do
      spammy_user = create(:spammy_user)
      create(:issue_comment, issue: @issue, user: spammy_user)
      discussion = create_converted_discussion
      create(:discussion_comment, discussion: discussion)

      verify!(discussion)
    end

    test "raises if comment counts do not match" do
      create(:issue_comment, issue: @issue)
      discussion = create_converted_discussion

      assert_raises IssueToDiscussionConversionVerifier::MissingCommentsError do
        verify!(discussion)
      end
    end
  end

  def verify!(discussion)
    IssueToDiscussionConversionVerifier.verify!(@issue, discussion)
  end

  def create_converted_discussion
    create(:discussion, repository: @repo, issue: @issue)
  end
end
