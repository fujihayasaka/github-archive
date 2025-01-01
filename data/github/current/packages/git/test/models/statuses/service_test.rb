# typed: true
# frozen_string_literal: true

require "test_helper"

class StatusesServiceTest < GitHub::TestCase

  include GitHub::DatabaseQueryWarningsTestHelpers

  fixtures do
    @user = create :user, login: "user", plan: "medium"
    @jumanji = create :repository, name: "jumanji", owner: @user, from_example: :mojombo_grit

    @sha1 = "1d22e6fde59c9ded9b8093cf26213a5bd9d4c5ec"
    @tree1 = "9ad5126eba69a9ab519e7bafe9328caff5c614cd"
    @sha2 = "86264f45ff4bcd3da195f5c83f7e414ed4a71628"
    @tree2 = "ad0e5c6cda4b7e2e46cc45e42a72eab4aa2e8109"
    @sha3 = "fb58d3284dbf05e05d8c2ab04ff5bfe853b67d88"

    @context = "my-very-important-status"

    reset_repo_root
    example_repo :mojombo_grit, @jumanji
  end

  context "#previous_status" do
    test "successfully gets last status" do
      status1 = create :status, sha: @sha1, state: "pending", creator: @user, repository: @jumanji, context: @context
      status2 = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: @context

      assert_nil status1.previous_status

      assert_equal status1, Statuses::Service.previous_status(repo_id: @jumanji.id, sha: @sha1, status_id: status2.id, context: @context)
      assert_equal status1, status2.previous_status
    end

    test "successfully gets last status in same context" do
      status1 = create :status, sha: @sha1, state: "pending", creator: @user, repository: @jumanji, context: @context
      status2 = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "anotha-one"
      status3 = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: @context

      assert_nil status1.previous_status
      assert_nil status2.previous_status

      assert_equal status1, Statuses::Service.previous_status(repo_id: @jumanji.id, sha: @sha1, status_id: status3.id, context: @context)
      assert_equal status1, status3.previous_status
    end
  end

  test "#count_per_sha_and_context" do
    status = create :status, sha: @sha1, state: "pending", context: "foo", creator: @user, repository: @jumanji
    assert_equal 1, Statuses::Service.count_per_sha_and_context(repo_id: @jumanji.id, sha: @sha1, context: "foo")
  end

  test "#count_per_sha_and_context with emoji" do
    assert_no_query_warnings do
      status = create :status, sha: @sha1, state: "pending", context: "foo", creator: @user, repository: @jumanji
      assert_equal 0, Statuses::Service.count_per_sha_and_context(repo_id: @jumanji.id, sha: @sha1, context: "foo #{GRIN_EMOJI}")
    end
  end

  context "#statuses_for_repo_exist?" do
    test "true" do
      status = create :status, sha: @sha1, state: "pending", context: "foo", creator: @user, repository: @jumanji
      assert Statuses::Service.statuses_for_repo_exist?(repository_id: @jumanji.id)
    end

    test "false" do
      repo = create :repository, name: "whatevs", owner: @user
      refute Statuses::Service.statuses_for_repo_exist?(repository_id: repo.id)
    end
  end

  context "#current_by_sha" do
    test "most recently created status is 'current'" do
      status1 = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji
      status2 = create :status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji
      status_other_oid = create :status, sha: @sha2, repository: @jumanji
      current = Statuses::Service.current_by_sha(repository_id: @jumanji.id, shas: [@sha1, @sha2])
      refute_includes current[@sha1], status1
      assert_includes current[@sha1], status2
      assert_includes current[@sha2], status_other_oid
    end

    test "most recently created status for a context is contextually current" do
      status1 = create :status, sha: @sha1, state: "failure", repository: @jumanji, context: "test context 1"
      status2 = create :status, sha: @sha1, state: "pending", repository: @jumanji, context: "test context"
      status3 = create :status, sha: @sha1, state: "success", repository: @jumanji, context: "test context"
      status4 = create :status, sha: @sha2, state: "success", repository: @jumanji, context: "test context"
      status_other_oid = create :status, sha: @sha2, repository: @jumanji, context: "test context"
      current = Statuses::Service.current_by_sha(repository_id: @jumanji.id, shas: [@sha1, @sha2])
      assert_includes current[@sha1], status1
      refute_includes current[@sha2], status2
      assert_includes current[@sha1], status3
      assert_includes current[@sha2], status_other_oid
    end
  end

  context ".current_for_shas" do
    test "for preview features repos" do
      Repository.any_instance.stubs(:preview_features?).returns(true)
      current = Set.new

      create(:status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji, context: "context 1")
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "context 1")

      create(:status, sha: @sha1, state: "pending", creator: @user, repository: @jumanji, context: "context 2")
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "context 2")

      # no given context is treated as its own context so that legacy contextless use works just like it used to.
      create(:status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji)
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji)

      # Only return statuses for the correct sha
      create(:status, sha: @sha2, state: "failure", creator: @user, repository: @jumanji, context: "context 1")

      assert_empty current.difference(Statuses::Service.current_for_shas(repository_id: @jumanji.id, shas: @sha1))
    end

    test "if there are multiple statuses per context, returns the current ones" do
      current = Set.new

      create(:status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji, context: "context 1")
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "context 1")

      create(:status, sha: @sha1, state: "pending", creator: @user, repository: @jumanji, context: "context 2")
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "context 2")

      # no given context is treated as its own context so that legacy contextless use works just like it used to.
      create(:status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji)
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji)

      # Only return statuses for the correct sha
      create(:status, sha: @sha2, state: "failure", creator: @user, repository: @jumanji, context: "context 1")

      assert_empty current.difference(Statuses::Service.current_for_shas(repository_id: @jumanji.id, shas: @sha1))
    end

    test "if there are multiple statuses per context, returns the current ones with pagination" do
      current = Set.new

      create(:status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji, context: "context 1")
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "context 1")

      create(:status, sha: @sha1, state: "pending", creator: @user, repository: @jumanji, context: "context 2")
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "context 2")

      # no given context is treated as its own context so that legacy contextless use works just like it used to.
      create(:status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji)
      current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji)

      # Only return statuses for the correct sha
      create(:status, sha: @sha2, state: "failure", creator: @user, repository: @jumanji, context: "context 1")

      assert_empty current.difference(Statuses::Service.current_for_shas(repository_id: @jumanji.id, shas: @sha1))
    end

    context ".current_for" do
      test "returns the current for a list of contexts, commit oids and tree oids" do
        current = Set.new

        create(:status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji, context: "context 1")
        current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "context 1")

        create(:status, sha: @sha1, state: "pending", creator: @user, repository: @jumanji, context: "context 2")
        current << create(:status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "context 2")

        create(:status, sha: @sha2, state: "pending", creator: @user, repository: @jumanji, context: "context 1")
        current << create(:status, sha: @sha2, state: "failure", creator: @user, repository: @jumanji, context: "context 1")

        create(:status, sha: @sha3, state: "failure", creator: @user, repository: @jumanji, context: "context 1")
        create(:status, sha: @sha3, state: "failure", creator: @user, repository: @jumanji, context: "context 2")

        commit_oids = [@sha1, @sha2]

        statuses = Statuses::Service.current_for(repo_id: @jumanji.id, contexts: ["context 1", "context 2"], commit_oids: commit_oids)
        assert_empty current.difference(statuses)
      end
    end

    test "does not raise any query warnings when passing 4 byte ut8 characters" do
      assert_no_query_warnings do
        assert_empty Statuses::Service.current_for(
          repo_id: @jumanji.id, contexts: ["context 🚀"], commit_oids: [GitHub::NULL_OID]
        )

        assert_empty Statuses::Service.current_for(
          repo_id: @jumanji.id, contexts: ["context 🚀", "other_context"], commit_oids: [GitHub::NULL_OID]
        )
      end
    end
  end

  context "paginated_statuses" do
    test "returns paginated relation" do
      status1 = create :status, sha: @sha1, state: "pending", creator: @user, repository: @jumanji
      status2 = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji

      result = Statuses::Service.paginated_statuses(repo_id: @jumanji.id, sha: @sha1, page: 1, per_page: 1)
      assert_equal [status2], result

      result = Statuses::Service.paginated_statuses(repo_id: @jumanji.id, sha: @sha1, page: 2, per_page: 1)
      assert_equal [status1], result
    end

    test "returns an empty collection when given a nil sha" do
      result = Statuses::Service.paginated_statuses(repo_id: @jumanji.id, sha: nil, page: 1, per_page: 1)
      assert_equal [], result
    end
  end

  context ".statuses_at_merge" do
    test "returns statuses grouped by context and ordered by id desc" do
      status1 = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "test", created_at: 3.minutes.ago
      create :status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji, context: "cla", created_at: 2.minutes.ago
      status3 = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "cla", created_at: 1.minute.ago

      statuses = Statuses::Service.statuses_at_merge(repository: @jumanji, sha: @sha1, merged_at: Time.current)
      assert_equal [status3, status1], statuses
    end

    test "uses case-insensitive context grouping" do
      test_status = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "test", created_at: 3.minutes.ago
      create :status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji, context: "cla", created_at: 2.minutes.ago
      uppercase_status = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "CLA", created_at: 1.minute.ago

      statuses = Statuses::Service.statuses_at_merge(repository: @jumanji, sha: @sha1, merged_at: Time.current)
      assert_equal [uppercase_status, test_status], statuses
    end

    test "excludes statuses created after merged_at" do
      create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "test", created_at: 2.minutes.ago
      create :status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji, context: "cla", created_at: 1.minute.ago
      status_after_merge = create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "after_merge"

      statuses = Statuses::Service.statuses_at_merge(repository: @jumanji, sha: @sha1, merged_at: status_after_merge.created_at - 1.second)
      refute_includes statuses, status_after_merge
    end

    test "excludes statuses for other shas" do
      create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "test", created_at: 2.minutes.ago
      create :status, sha: @sha1, state: "failure", creator: @user, repository: @jumanji, context: "cla", created_at: 1.minute.ago
      status_for_sha2 = create :status, sha: @sha2, state: "failure", creator: @user, repository: @jumanji, context: "sha2", created_at: 1.minute.ago

      statuses = Statuses::Service.statuses_at_merge(repository: @jumanji, sha: @sha1, merged_at: Time.current)
      refute_includes statuses, status_for_sha2
    end
  end

  context ".recent_status_contexts_and_integrations" do
    test "returns integrations grouped by context" do
      bot = create(:bot)
      other_bot = create(:bot)
      create :status, sha: @sha1, state: "success", creator: bot, repository: @jumanji, context: "test", created_at: 2.minutes.ago
      create :status, sha: @sha1, state: "success", creator: other_bot, repository: @jumanji, context: "test", created_at: 1.minute.ago
      create :status, sha: @sha1, state: "failure", creator: bot, repository: @jumanji, context: "cla", created_at: 1.minute.ago
      create :status, sha: @sha1, state: "success", creator: @user, repository: @jumanji, context: "hand_crafted", created_at: 1.minute.ago

      statuses = Statuses::Service.recent_status_contexts_and_integrations(repo_id: @jumanji.id, start: 3.minutes.ago, limit: 20)
      assert_equal(
        {
          "test" => Set[bot.integration, other_bot.integration],
          "cla" => Set[bot.integration],
          "hand_crafted" => Set[],
        },
        statuses,
      )
    end

    test "orders by created_at" do
      bot = create(:bot)
      limit = 5

      (1..limit).each do |i|
        create :status, sha: @sha1, state: "success", creator: bot, repository: @jumanji, context: SecureRandom.uuid, created_at: i.minutes.ago
      end

      latest_status = create :status, sha: @sha1, state: "success", creator: bot, repository: @jumanji, context: "latest"

      statuses = Statuses::Service.recent_status_contexts_and_integrations(repo_id: @jumanji.id, start: (limit + 1).minutes.ago, limit: limit)
      assert statuses.has_key? latest_status.context
    end
  end
end
