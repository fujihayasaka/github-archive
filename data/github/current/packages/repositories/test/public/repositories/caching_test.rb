# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryDomainCachingTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    @by_qualified_name_query_count = 1
  end

  setup do
    GH::Context.__reset
    enable_feature_flag(:domain_caching_repositories_repositories_by_qualified_name)
    enable_feature_flag(:domain_caching_repositories_repositories_active_by_id)
    enable_feature_flag(:domain_id_caching_repositories_repositories_by_id)
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  test "cached repo only does 1 query" do
    GH::Context.enabled do
      assert_query_count_per_table({ repositories: 1 }) do
        r1 = Repositories.domain.by_id(@repo.id)
        r2 = Repositories.domain.by_id(@repo.id)
        assert r1
        assert_equal T.must(r1).id, T.must(r2).id
        refute_equal T.must(r1).object_id, T.must(r2).object_id
      end
    end
  end

  test "cached repo via name then lookup by id only does 1 query" do
    GH::Context.enabled do
      assert_query_count_per_table({ repositories: @by_qualified_name_query_count }) do
        r1 = Repositories.domain.by_qualified_name(@repo.nwo)
        r2 = Repositories.domain.by_id(@repo.id)
        assert r1
        assert_equal T.must(r1).id, T.must(r2).id
        refute_equal T.must(r1).object_id, T.must(r2).object_id
      end
    end
  end

  test "cached repo via name then mutated then lookup by id does 2 queries" do
    GH::Context.enabled do
      r1 = assert_query_count_per_table({ repositories: @by_qualified_name_query_count }) do
        Repositories.domain.by_qualified_name(@repo.nwo)
      end

      @repo.update(name: "new-name")

      r2 = assert_query_count_per_table({ repositories: 1 }) do
        Repositories.domain.by_id(@repo.id)
      end

      assert r1
      assert_equal T.must(r1).id, T.must(r2).id
      refute_equal T.must(r1).object_id, T.must(r2).object_id
    end
  end

  test "cached repo via name then mutated then lookup via name does 2 queries" do
    GH::Context.enabled do
      r1 = assert_query_count_per_table({ repositories: @by_qualified_name_query_count }) do
        Repositories.domain.by_qualified_name(@repo.nwo)
      end

      @repo.update(name: "new-name")

      r2 = assert_query_count_per_table({ repositories: @by_qualified_name_query_count }) do
        Repositories.domain.by_qualified_name(@repo.nwo)
      end

      assert r1
      assert_equal T.must(r1).id, T.must(r2).id
      refute_equal T.must(r1).object_id, T.must(r2).object_id
    end
  end

  test "cached repo via id then mutated then lookup by name does 2 queries" do
    GH::Context.enabled do
      r1 = assert_query_count_per_table({ repositories: 1 }) do
        Repositories.domain.by_id(@repo.id)
      end

      @repo.update(name: "new-name")

      r2 = assert_query_count_per_table({ repositories: @by_qualified_name_query_count }) do
        Repositories.domain.by_qualified_name(@repo.nwo)
      end

      assert r1
      assert_equal T.must(r1).id, T.must(r2).id
      refute_equal T.must(r1).object_id, T.must(r2).object_id
    end
  end

  test "creating a repo clears the cache" do
    GH::Context.enabled do
      r1 = assert_query_count_per_table({ repositories: 1 }) do
        Repositories.domain.by_id(1234567)
      end

      repo = create(:repository, owner: @user, id: 1234567)

      r2 = assert_query_count_per_table({ repositories: 1 }) do
        Repositories.domain.by_id(1234567)
      end

      refute r1
      assert r2
    end
  end

  test "updating a repo clears the cache" do
    GH::Context.enabled do
      r1 = assert_query_count_per_table({ repositories: 1 }) do
        Repositories.domain.by_id(@repo.id)
      end

      @repo.update(name: "new-name")

      r2 = assert_query_count_per_table({ repositories: 1 }) do
        Repositories.domain.by_id(@repo.id)
      end

      assert r1
      assert_equal T.must(r1).id, T.must(r2).id
      refute_equal T.must(r1).object_id, T.must(r2).object_id
    end
  end

  test "destroying a repo clears the cache" do
    GH::Context.enabled do
      r1 = assert_query_count_per_table({ repositories: 1 }) do
        Repositories.domain.by_id(@repo.id)
      end

      @repo.destroy

      r2 = assert_query_count_per_table({ repositories: 1 }) do
        Repositories.domain.by_id(@repo.id)
      end

      assert r1
      refute r2
    end
  end

  test "can cache null result via id" do
    GH::Context.enabled do
      assert_query_count_per_table({ repositories: 1 }) do
        r1 = Repositories.domain.by_id(1234567)
        r2 = Repositories.domain.by_id(1234567)

        refute r1
        refute r2
      end
    end
  end

  test "can cache null result via method" do
    GH::Context.enabled do
      assert_query_count_per_table({ repositories: @by_qualified_name_query_count }) do
        r1 = Repositories.domain.by_qualified_name("cantbe/real")
        r2 = Repositories.domain.by_qualified_name("cantbe/real")

        refute r1
        refute r2
      end
    end
  end

  test "active_by_id then by_id then active_by_id only does 1 query" do
    GH::Context.enabled do
      assert_query_count_per_table({ repositories: 1 }) do
        # memoize + populate ID cache
        r1 = Repositories.domain.active_by_id(@repo.id)
        # hits ID cache
        r2 = Repositories.domain.by_id(@repo.id)
        # hits memoization
        r3 = Repositories.domain.active_by_id(@repo.id)
        assert r1
        assert r2
        assert r3
        assert_equal T.must(r1).id, T.must(r2).id
        assert_equal T.must(r1).id, T.must(r3).id
        refute_equal T.must(r1).object_id, T.must(r2).object_id
        refute_equal T.must(r1).object_id, T.must(r3).object_id
      end
    end
  end

  context "dogstats works" do
    test "id caching" do
      GH::Context.enabled do
        assert_query_count_per_table({ repositories: 1 }) do
          r1 = Repositories.domain.by_id(@repo.id)
          r2 = Repositories.domain.by_id(@repo.id)
          assert r1
          assert_equal T.must(r1).id, T.must(r2).id
        end
      end

      expected_tags = ["domain:packages/repositories", "accessor:repositories", "hit:false"]
      assert_dogstats_count 1, "domain.call.id_cache", tags: expected_tags

      expected_tags = ["domain:packages/repositories", "hit:true"]
      assert_dogstats_count 1, "domain.call.id_cache", tags: expected_tags
    end

    test "method caching" do
      repo2 = create(:repository, owner: @user)

      GH::Context.enabled do
        assert_query_count_per_table({ repositories: @by_qualified_name_query_count }) do
          Repositories.domain.by_qualified_name(@repo.nwo)
          Repositories.domain.by_qualified_name(@repo.nwo)
        end

        Repositories.domain.by_qualified_name(repo2.nwo)
      end

      expected_tags = ["domain:packages/repositories", "accessor:repositories", "method:by_qualified_name", "hit:false"]
      assert_dogstats_count 2, "domain.call.method_cache", tags: expected_tags

      expected_tags = ["domain:packages/repositories", "accessor:repositories", "method:by_qualified_name", "hit:true"]
      assert_dogstats_count 1, "domain.call.method_cache", tags: expected_tags
    end
  end
end
