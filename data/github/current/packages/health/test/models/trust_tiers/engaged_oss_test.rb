# typed: true
# frozen_string_literal: true

require "test_helper"

class TrustTiers::EngagedOssTest < GitHub::TestCase
  fixtures do
    @public_repo = create(:public_repository, name: "public-repo-1", created_at: 2.months.ago, pushed_at: 2.years.ago)
    @private_repo = create(:private_repository, name: "private-repo-1")

    make_searchable @public_repo
    make_searchable @private_repo
  end

  test "populate OOS repos cache and public repo is cached" do
    # using a query similar to the one used in the EngagedOss model but without the stars filter
    query_phrase = "is:public archived:false fork:false
                  created:<#{1.month.ago.strftime("%Y-%m-%d")}
                  pushed:>#{1.year.ago.strftime("%Y-%m-%d")}"
    repos = TrustTiers::EngagedOss.get_repos(query_phrase)
    TrustTiers::EngagedOss.populate_repos(repos)

    assert_equal true, TrustTiers::EngagedOss.is_repo_engaged_oss?(@public_repo.id)
  end

  test "populate OOS repos cache and private repo is not cached" do
    repos = TrustTiers::EngagedOss.get_repos("is:public")
    TrustTiers::EngagedOss.populate_repos(repos)

    assert_equal false, TrustTiers::EngagedOss.is_repo_engaged_oss?(@private_repo.id)
  end

  test "KV cache is unavailable and engaged oss repo is in the persisted file" do
    repos = TrustTiers::EngagedOss.get_repos("is:public")
    TrustTiers::EngagedOss.populate_repos(repos)

    # stub KV to raise an error
    Spam::Kv.store.stubs(:exists).raises(GitHub::KV::UnavailableError)

    engaged_oss_repo_id = 1

    assert_equal true, TrustTiers::EngagedOss.is_repo_engaged_oss?(engaged_oss_repo_id)
  end

  test "KV cache is unavailable and engaged oss repo is not in the persisted file" do
    repos = TrustTiers::EngagedOss.get_repos("is:public")
    TrustTiers::EngagedOss.populate_repos(repos)

    # stub KV to raise an error
    Spam::Kv.store.stubs(:exists).raises(GitHub::KV::UnavailableError)

    not_engaged_oss_repo_id = 2

    assert_equal false, TrustTiers::EngagedOss.is_repo_engaged_oss?(not_engaged_oss_repo_id)
  end
end
