# typed: true
# frozen_string_literal: true

require "test_helper"

class Repositories::Domain::Contents::GetCommitDateTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository, from_example: :repository_contents_test)
  end

  setup do
    enable_cache_storage
    reset_cache
    Spokesd.enable_spokesd
  end

  teardown do
    disable_cache_storage
  end

  test "get_commit_date" do
    commit_date = Repositories.domain.contents.get_commit_date(repository: @repo, oid: "f4dc787c810b20ab2dbfbf876c19f602b5f4e61a")

    assert_equal(Time.utc(2024, 12, 9, 4, 22, 56, 0).getlocal("-08:00"), commit_date)
  end

  test "return cached result" do
    repository = create(:repository, from_example: :repository_contents_test)

    GitHub.dogstats.reset
    original_commit_date = Repositories.domain.contents.get_commit_date(repository: repository, oid: "f4dc787c810b20ab2dbfbf876c19f602b5f4e61a")
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:get_commit_date", "result:miss"])

    perform_commit_to(repository, "main")

    GitHub.dogstats.reset
    commit_date = Repositories.domain.contents.get_commit_date(repository: repository, oid: "f4dc787c810b20ab2dbfbf876c19f602b5f4e61a")
    assert_equal(original_commit_date, commit_date)
    assert_dogstats_increment("cache_get.contents_domain", tags: ["method:get_commit_date", "result:hit"])
  end

  def perform_commit_to(repository, ref)
    repository.heads.find(ref).append_commit({
      message: "change stuff",
      committer: repository.owner,
      author: repository.owner,
    }, repository.owner)
  end
end
