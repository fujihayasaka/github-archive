# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueAutonumberingTest < GitHub::TestCase
  fixtures do
    @repo  = create(:repository)
    @owner = @repo.owner
    @issue = create :issue, repository: @repo, user: @owner
  end

  test "creates with incrementing number" do
    assert_equal Sequence.get(@repo), @issue.number

    issue1 = create :issue, repository: @repo, user: @owner
    issue2 = create :issue, repository: @repo, user: @owner
    assert_equal @issue.number + 1, issue1.number
    assert_equal @issue.number + 2, issue2.number
  end

  test "can set new number" do
    number = @issue.number + 5000
    issue = build :issue, repository: @repo, user: @owner, number: number
    assert_valid issue
    assert issue.save
    assert_equal number, issue.number
    assert_equal number, Sequence.get(@repo), "set sequence to new number"
  end

  test "can set new number used in another repo" do
    other_repo = create(:repository)
    number = @issue.number + 5000
    issue1 = build :issue, repository: other_repo, user: @owner, number: number
    assert_valid issue1
    assert issue1.save
    assert_equal number, issue1.number

    issue2 = build :issue, repository: @repo, user: @owner, number: number
    assert_valid issue2
    assert issue2.save
    assert_equal number, issue2.number

    assert_equal number, Sequence.get(@repo), "set sequence to new number"
  end

  test "cannot set duplicate number" do
    issue = build :issue, repository: @repo, user: @owner, number: @issue.number
    assert_valid issue
    assert issue.save
    refute_equal @issue.number, issue.number
    assert_equal @issue.number + 1, issue.number
  end

  test "respects gaps in the sequence" do
    # skip 10 numbers in the sequence
    Sequence.next(@repo, 10)

    issue = create :issue, repository: @repo
    assert_equal issue.number, Sequence.get(@repo)
  end

  test "can set number less than the sequence so long as the number doesn't exist" do
    Sequence.next(@repo, 10)

    issue = build :issue, repository: @repo, user: @owner,
      number: @issue.number
    assert_valid issue
    assert issue.save
    refute_equal issue.number, @issue.number
    current_sequenece = Sequence.get(@repo)
    assert_equal current_sequenece, issue.number

    issue = build :issue, repository: @repo, user: @owner,
      number: @issue.number + 1
    assert_valid issue
    assert issue.save
    assert_equal issue.number, @issue.number + 1
    assert_equal Sequence.get(@repo), current_sequenece
  end
end
