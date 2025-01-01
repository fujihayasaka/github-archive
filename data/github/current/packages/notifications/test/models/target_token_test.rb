# typed: true
# frozen_string_literal: true

require "test_helper"

class EmailReplyTargetTokensTest < GitHub::TestCase
  fixtures do
    @sender = create :user, plan: "large"
    @recipient = create(:user)
    @repo = create :repository, owner: @sender
    @issue = create :issue, repository: @repo, user: @sender
  end

  [Issue, PullRequestReviewComment, CommitComment].each do |klass|
    test "creates email token for #{klass}" do
      target = klass.new
      target.id = 55
      token = GitHub::Email::Token.target_token(target, @recipient)
      klass.expects(:find_by_id).with(55).returns(target)
      assert_equal target, GitHub::Email::Token.target_from_token(token, @recipient)
    end
  end

  [PullRequest, IssueComment].each do |klass|
    test "creates email token for #{klass}" do
      target = klass.new
      target.issue = @issue
      target.id = 1
      token = GitHub::Email::Token.target_token(target, @recipient)
      assert_equal target.issue, GitHub::Email::Token.target_from_token(token, @recipient)
    end
  end

  test "creates email token for IssueEvent" do
    event = IssueEvent.new
    event.id = 400
    event.issue = @issue
    target = IssueEventNotification.new(event)
    token = GitHub::Email::Token.target_token(target, @recipient)
    assert_equal event.issue, GitHub::Email::Token.target_from_token(token, @recipient)
  end

  test "cannot create email token for User" do
    assert_raises GitHub::Email::Token::UnknownTargetToken do
      GitHub::Email::Token.target_token(@sender, nil)
    end
  end

  test "finds message from email token" do
    token = GitHub::Email::Token.target_token(@issue, @recipient)
    assert_equal @issue, GitHub::Email::Token.target_from_token(token, @recipient)
    assert_nil GitHub::Email::Token.target_from_token(GitHub::Email::Token.target_token(@issue, @sender), @recipient)
  end
end
