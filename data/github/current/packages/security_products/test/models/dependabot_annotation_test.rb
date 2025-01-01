# typed: true
# frozen_string_literal: true

require "test_helper"

class DependabotAnnotationTest < GitHub::TestCase
  DataMock = Struct.new(:result, :results, :number)
  fixtures do
    @dependabot_annotation = create(:dependabot_annotation)
  end

  test "is deleted after check annotation destruction" do
    assert_difference('DependabotAnnotation.annotate("cross-shard-query-exempted").count', -1) do
      @dependabot_annotation.check_annotation.destroy
    end
  end

  test "is deleted after repository soft-deletion" do
    repo = @dependabot_annotation.check_annotation.check_run.repository

    assert_difference('DependabotAnnotation.annotate("cross-shard-query-exempted").count', -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.remove(repo.owner, synchronous: true)
      end
    end
  end

  test "validation fails if repository_id does not match check_run's repository_id" do
    # Create a check_run with a different repository
    check_run = create(:check_run)
    different_repository = create(:repository)

    dependabot_annotation = build(:dependabot_annotation, check_run: check_run, repository: different_repository)

    # The record should be invalid
    assert_not dependabot_annotation.valid?
    assert_includes dependabot_annotation.errors[:repository], "does not match the check run's repository"
  end

  test "validation fails if repository_id does not match check_annotation's repository_id" do
    # Create a check_annotation with a different repository
    check_annotation = create(:check_annotation)
    different_repository = create(:repository)

    dependabot_annotation = build(:dependabot_annotation, check_annotation: check_annotation, repository: different_repository)

    # The record should be invalid
    assert_not dependabot_annotation.valid?
    assert_includes dependabot_annotation.errors[:repository], "does not match the check annotation's repository"
  end
end
