# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryMirrorJobTest < GitHub::TestCase
  fixtures do
    @repo = create :mirror_repository
  end

  test "should cache mirror status on successful perform" do
    refute Repositories::Kv.store.get("mirror-timestamp:#{@repo.id}").value!
    refute Repositories::Kv.store.get("mirror-result:#{@repo.id}").value!

    Mirror.any_instance.stubs(:perform!)
    RepositoryMirrorJob.perform_now(@repo.id)

    assert Repositories::Kv.store.get("mirror-timestamp:#{@repo.id}").value!
    assert_equal "success", Repositories::Kv.store.get("mirror-result:#{@repo.id}").value!
  end

  test "should cache mirror failure status on unsuccessful perform" do
    refute Repositories::Kv.store.get("mirror-timestamp:#{@repo.id}").value!
    refute Repositories::Kv.store.get("mirror-result:#{@repo.id}").value!

    assert_raises(RepositoryMirrorJob::Failed) do
      Mirror.any_instance.stubs(:perform!).raises(Repository::CommandFailed.new("one", "two", "three"))
      RepositoryMirrorJob.perform_now(@repo.id)
    end

    assert Repositories::Kv.store.get("mirror-timestamp:#{@repo.id}").value!
    assert_equal "failed", Repositories::Kv.store.get("mirror-result:#{@repo.id}").value!
  end

  test "doesn't cache values when kv is down" do
    result = GitHub::Result.new { raise "Some GitHub::KV Failure" }
    Repositories::Kv.store.stubs(:set).returns(result)
    RepositoryMirrorJob.new.set_status_in_cache("mirror-result:#{@repo.id}", "success")

    refute Repositories::Kv.store.get("mirror-timestamp:#{@repo.id}").value!
    refute Repositories::Kv.store.get("mirror-result:#{@repo.id}").value!
  end

  test "should catch unexpected exceptions" do
    assert_raises(RepositoryMirrorJob::Failed) do
      Mirror.any_instance.stubs(:perform!).raises(GitRPC::InvalidRepository.new("this is a test"))
      RepositoryMirrorJob.perform_now(@repo.id)
    end
  end

end
