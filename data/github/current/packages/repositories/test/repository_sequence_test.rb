# typed: strict
# frozen_string_literal: true

require "test_helper"

class RepositorySequenceDependencyMethodsTest < GitHub::TestCase
  test "creates a sequence when a repository is created" do
    repo = build(:repository)
    assert !Sequence.exists?(repo), "sequence should not exist"
    repo.save!
    assert Sequence.exists?(repo), "sequence should exist"
  end

  context "duplicate issues" do
    test "fixes two duplicate issues" do
      repo = create(:repository)
      issue1 = create(:issue, repository: repo)
      issue2 = create(:issue, repository: repo)
      issue2.update_column(:number, issue1.number)

      assert_equal 2, repo.issues.count
      assert_equal issue1.number, issue2.number

      repo.fix_duplicate_sequence_for_issue(number: issue1.number)

      refute_equal issue1.reload.number, issue2.reload.number
    end

    test "raises on six duplicate issues" do
      repo = create(:repository)
      issue1 = create(:issue, repository: repo)
      5.times do
        issue = create(:issue, repository: repo)
        issue.update_column(:number, issue1.number)
      end

      assert_equal 6, repo.issues.count
      assert_equal 1, repo.issues.pluck(:number).uniq.size

      assert_raises_with_message(RuntimeError, "Too many duplicate issues (5) for repo #{repo.id} issue \##{issue1.number}") do
        repo.fix_duplicate_sequence_for_issue(number: issue1.number)
      end
    end
  end
end
