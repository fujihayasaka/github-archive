# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeScanningCheckSuiteTest < GitHub::TestCase
  fixtures do
    @cs_check_suite = create(:code_scanning_check_suite)
  end

  test "is deleted after check suite destruction" do
    assert_difference("CodeScanningCheckSuite.where(repository_id: #{@cs_check_suite.repository_id}).count", -1) do
      @cs_check_suite.check_suite.destroy
    end
  end

  test "is deleted after repository destruction" do
    repo = @cs_check_suite.repository
    repo.remove(repo.owner, synchronous: true)

    assert_difference("CodeScanningCheckSuite.where(repository_id: #{@cs_check_suite.repository_id}).count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        repo.purge(synchronous: true)
      end
    end
  end

  test "for_check_run" do
    check_run = create(:check_run, check_suite: @cs_check_suite.check_suite)
    assert_equal @cs_check_suite, CodeScanningCheckSuite.for_check_run(check_run)
  end
end
