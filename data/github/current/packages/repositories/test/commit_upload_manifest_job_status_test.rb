# typed: strict
# frozen_string_literal: true

require "test_helper"

class CommitUploadManifestJobStatusTest < GitHub::TestCase
  fixtures do
  end

  test "create generates a specific ID prefix" do
    status = CommitUploadManifestJobStatus.create

    assert status.id.starts_with?(CommitUploadManifestJobStatus::ID_PREFIX)
  end

  test "job_id adds ID prefix to numeric id" do
    job_id = CommitUploadManifestJobStatus.job_id(17)

    assert_equal "commit_upload_manifest_17", job_id
  end

  test "uploader_id is set on initialization" do
    status = CommitUploadManifestJobStatus.create(id: 17, uploader_id: 2)

    assert_equal 2, status.uploader_id
  end

  test "error allows recording of failed runs" do
    status = CommitUploadManifestJobStatus.create(id: 17, uploader_id: 3)
    expected_metadata = {
      "README.md" => "metadata for README.md",
      "test.txt" => "metadata for test.txt"
    }
    failed_runs = [
      RuleEngine::RuleRun.new(
        rule_provider: "foo_rule_provider",
        rule_type: "test_rule_type",
        result: "failed",
        evaluation_metadata: expected_metadata
      ),
      RuleEngine::RuleRun.new(
        rule_provider: "bar_rule_provider",
        rule_type: "test_rule_type",
        result: "failed"
      )
    ]
    status.error!("something went wrong", failed_runs)

    assert_equal 3, status.uploader_id
    assert_equal failed_runs, status.failed_runs
    assert_equal expected_metadata, T.must(T.must(status.failed_runs).first).evaluation_metadata
  end
end
