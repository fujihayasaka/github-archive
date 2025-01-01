# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SetupIssueTypesForOrganizationJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @org = create(:organization, exclude_issue_types: true)
  end

  test "retries on dirty exit" do
    assert_retry_on_dirty_exit job: SetupIssueTypesForOrganizationJob
  end

  test "retries on recoverable exceptions" do
    assert_retry_on_recoverable_exceptions job: SetupIssueTypesForOrganizationJob
  end

  test "creates default issue types for an org which has no types yet" do
    assert_empty @org.issue_types
    SetupIssueTypesForOrganizationJob.perform_now(org: @org)
    assert_equal 3, @org.reload.issue_types.count
  end

  test "does not create more default issue types for an org which for some reason has them already" do
    assert_empty @org.issue_types
    IssueType.create_default_issue_types_for(@org)
    assert_equal 3, @org.reload.issue_types.count
    SetupIssueTypesForOrganizationJob.perform_now(org: @org)
    assert_equal 3, @org.reload.issue_types.count
  end

  test "creates remaining issue types if the job failed halfway through" do
    assert_empty @org.issue_types
    IssueType.create_default_issue_types_for(@org)
    # Simulating a job that failed halfway through
    IssueType.find_by(name: "bug")&.delete
    IssueType.find_by(name: "feature")&.delete

    SetupIssueTypesForOrganizationJob.perform_now(org: @org.reload)
    assert_equal 3, @org.reload.issue_types.count
  end
end
