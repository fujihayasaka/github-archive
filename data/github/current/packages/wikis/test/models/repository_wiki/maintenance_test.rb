# typed: true
# frozen_string_literal: true

require "test_helper"

class WikiMaintenanceTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @repo  = create(:repository, owner: @owner)
  end

  setup do
    @repo.initialize_wiki(@owner)
    @repo.reload
    @wiki = RepositoryWiki.find_by(repository: @repo)

    @spawn_res_ok =     { "argv" => ["foo"], "out" => "", "ok" => true, "status" => 0, "err" => "sync: 92800494.git: +64K\nRunning git-repack" }
    @spawn_res_locked = { "argv" => ["foo"], "out" => "", "ok" => false, "status" => 2, "err" => "fatal: could not get the nw-sync lock. sync already in progress." }
  end

  test "perform_maintenance succeeds" do
    @wiki.perform_maintenance
    assert_equal "complete", @wiki.attributes["maintenance_status"]
  end

  test "running maintenance is retried when one backend is locked" do
    assert_equal "complete", @wiki.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:spawn).returns(@spawn_res_locked, @spawn_res_ok, @spawn_res_locked, @spawn_res_ok, @spawn_res_locked, @spawn_res_ok)
    @wiki.perform_maintenance
    assert_equal "retry", @wiki.attributes["maintenance_status"]
  end

  test "running maintenance with repack errors fails" do
    assert_equal "complete", @wiki.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).raises(::GitRPC::Error)
    assert_raises(::GitRPC::Error) do
      @wiki.perform_maintenance
    end
    assert_equal "failed", @wiki.attributes["maintenance_status"]
  end
end
