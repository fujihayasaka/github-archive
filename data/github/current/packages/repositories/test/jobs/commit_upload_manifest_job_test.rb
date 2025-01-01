# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitUploadManifestJobTest < GitHub::TestCase
  fixtures do
    @manifest = create(:upload_manifest)
  end

  def assert_failure_conditions(find_manifest: true, find_job_status: true)
    if find_job_status
      assert job_status = CommitUploadManifestJobStatus.find!(CommitUploadManifestJobStatus.job_id(@manifest.id))
      assert_predicate job_status, :error?
    end

    if find_manifest
      assert manifest = UploadManifest.find(@manifest.id)
      assert_predicate manifest, :state_failed?

      ctx = Failbot.squash_contexts(Failbot.context)
      assert_equal @manifest.repository.id, ctx["gh.repo.id"]
      assert_equal @manifest.uploader.id, ctx["gh.user.id"]
    end
  end

  test "retries if the manifest is not found" do
    assert_performed_jobs(CommitUploadManifestJob::MAX_ATTEMPTS) do
      assert_raises(ActiveRecord::RecordNotFound) do
        CommitUploadManifestJob.perform_later(@manifest.id + 1, CommitUploadManifestJobStatus.job_id(@manifest.id))
      end

      assert_failure_conditions(find_manifest: false, find_job_status: false)
    end
  end

  test "logs specific error when request too large error occurs" do
    request_too_large_error = "The file is too large and cannot be uploaded. Consider creating the file in a " \
        "local clone and pushing it to GitHub"
    UploadManifest.any_instance.stubs(:commit).raises(GitRPC::RequestTooLarge.new(1))

    CommitUploadManifestJob.perform_now(@manifest.id)

    assert job_status = CommitUploadManifestJobStatus.find!(CommitUploadManifestJobStatus.job_id(@manifest.id))
    assert_predicate job_status, :error?
    assert_match request_too_large_error, job_status.error_message
  end

  test "logs specific error when repo rule violation occurs" do
    rule_violation_error = "Secret detected in content"
    RuleEngine::RuleSuite.any_instance.stubs(:failure_messages).returns([rule_violation_error])
    UploadManifest.any_instance.stubs(:commit).raises(::Git::Ref::RepositoryRuleViolationError.new(RuleEngine::RuleSuite.new))

    CommitUploadManifestJob.perform_now(@manifest.id)

    assert job_status = CommitUploadManifestJobStatus.find!(CommitUploadManifestJobStatus.job_id(@manifest.id))
    assert_predicate job_status, :error?
    assert_match rule_violation_error, job_status.error_message
  end

  CommitUploadManifestJob::RETRY_ERRORS.each do |ex|
    test "retries if #{ex.name} is raised" do
      UploadManifest.any_instance.stubs(:commit).raises(ex.new("BOOM"))

      assert_performed_jobs(CommitUploadManifestJob::MAX_ATTEMPTS) do
        assert_raises(ex) do
          CommitUploadManifestJob.perform_later(@manifest.id)
        end
        assert_failure_conditions
      end
    end
  end

  [UploadManifest, CommitUploadManifestJobStatus].each do |model|
    test "retries for throttling from #{model}" do
      model.stubs(:throttle).raises(Freno::Throttler::Error)

      assert_performed_jobs(10) do
        assert_raises(Freno::Throttler::Error) do
          CommitUploadManifestJob.perform_later(@manifest.id, CommitUploadManifestJobStatus.job_id(@manifest.id))
        end
      end
    end
  end

  test "delegates to the model and updates the status" do
    upload_sequence = sequence("upload_sequence")
    CommitUploadManifestJobStatus.any_instance.expects(:started!).in_sequence(upload_sequence)
    UploadManifest.any_instance.expects(:commit).in_sequence(upload_sequence)
    CommitUploadManifestJobStatus.any_instance.expects(:success!).in_sequence(upload_sequence)

    CommitUploadManifestJob.perform_now(@manifest.id)
  end

  test "updates the job status and failbot context if there is an exception" do
    UploadManifest.any_instance.stubs(:commit).raises(StandardError.new("BOOM!"))
    assert_raises StandardError do
      CommitUploadManifestJob.perform_now(@manifest.id)
    end
  end
end
