# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryMirrorJobTest < GitHub::TestCase
  fixtures do
    @repo = create :mirror_repository
  end

  test "should cache mirror status on successful perform" do
    refute GitHub.kv.get("mirror-timestamp:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    refute GitHub.kv.get("mirror-result:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv

    Mirror.any_instance.stubs(:perform!)
    RepositoryMirrorJob.perform_now(@repo.id)

    assert GitHub.kv.get("mirror-timestamp:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    assert_equal "success", GitHub.kv.get("mirror-result:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  test "should cache mirror failure status on unsuccessful perform" do
    refute GitHub.kv.get("mirror-timestamp:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    refute GitHub.kv.get("mirror-result:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv

    assert_raises(RepositoryMirrorJob::Failed) do
      Mirror.any_instance.stubs(:perform!).raises(Repository::CommandFailed.new("one", "two", "three"))
      RepositoryMirrorJob.perform_now(@repo.id)
    end

    assert GitHub.kv.get("mirror-timestamp:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    assert_equal "failed", GitHub.kv.get("mirror-result:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  test "doesn't cache values when kv is down" do
    result = GitHub::Result.new { raise "Some GitHub::KV Failure" }
    GitHub.kv.stubs(:set).returns(result) # rubocop:todo GitHub/DoNotUseGlobalKv
    RepositoryMirrorJob.new.set_status_in_cache("mirror-result:#{@repo.id}", "success")

    refute GitHub.kv.get("mirror-timestamp:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
    refute GitHub.kv.get("mirror-result:#{@repo.id}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
  end

  test "should catch unexpected exceptions" do
    assert_raises(RepositoryMirrorJob::Failed) do
      Mirror.any_instance.stubs(:perform!).raises(GitRPC::InvalidRepository.new("this is a test"))
      RepositoryMirrorJob.perform_now(@repo.id)
    end
  end

end
