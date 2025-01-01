# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeqlDatabaseTest < GitHub::TestCase
  include UploadableTestHelpers

  self.strict_fixtures = true
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    Timecop.freeze(1.day.ago) do
      %w[ruby java].each do |language|
        create(:codeql_database, repository: @repo, language: language, uploader: @user)
      end

      @go_db = create(:codeql_database, repository: @repo, language: "go", uploader: @user)
    end

    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)
  end

  test "storage_s3_key is correct" do
    db = create(:codeql_database, repository: create(:repository, id: 1234), language: "go", guid: "abcdefg")
    assert_equal "database/1234/go/abcdefg", db.storage_s3_key(nil)
  end

  test "requires a valid size" do
    db = CodeqlDatabase.new uploader: @user, repository: @repo, language: "go", content_type: "application/zip", size: 0
    refute_predicate db, :valid?
    db.size = 2.gigabytes - 1
    assert_predicate db, :valid?
    db.size = 2.gigabytes + 1
    refute_predicate db, :valid?
  end

  context "#repos_and_languages_with_database" do
    test "doesn't error on empty list" do
      assert_equal Set.new, CodeqlDatabase.repos_and_languages_with_database([])
    end

    test "returns true when a database exists for that repo/language" do
      assert_equal [[@repo.id, "ruby"], [@repo.id, "go"]].to_set, CodeqlDatabase.repos_and_languages_with_database([[@repo.id, "ruby"], [@repo.id, "go"], [@repo.id, "cpp"]])
    end

    test "ignores databases not in the :uploaded state" do
      # Create a database for cpp, but is not in the :uploaded state
      create(:codeql_database, repository: @repo, language: "cpp", state: "starter")

      assert_equal Set.new, CodeqlDatabase.repos_and_languages_with_database([[@repo.id, "cpp"]])
    end

    test "handles and filters out non-existent repos" do
      assert_equal Set.new, CodeqlDatabase.repos_and_languages_with_database([[10001, "javascript"]])
    end

    test "handles and filters out invalid languages" do
      assert_equal Set.new, CodeqlDatabase.repos_and_languages_with_database([[@repo.id, "rubbish"]])
    end
  end

  context "#latest_for_repos_and_languages" do
    test "doesn't error on empty list" do
      assert_equal Hash.new, CodeqlDatabase.latest_for_repos_and_languages([])
    end

    test "returns only latest database" do
      # Create an old database
      Timecop.freeze(3.days.ago) do
        create(:codeql_database, repository: @repo, language: "ruby")
      end
      # Create two "new" databases with the exact same timestamp.
      # The second one (with the higher ID) will be considered to be the "latest".
      repo_latest_db = Timecop.freeze do
        create(:codeql_database, repository: @repo, language: "ruby")
        create(:codeql_database, repository: @repo, language: "ruby")
      end

      dbs = CodeqlDatabase.latest_for_repos_and_languages([[@repo.id, "ruby"], [@repo.id, "go"]])

      refute_nil dbs[[@repo.id, "ruby"]]
      assert_equal repo_latest_db.id, dbs[[@repo.id, "ruby"]].id

      refute_nil dbs[[@repo.id, "go"]]
      assert_equal @go_db.id, dbs[[@repo.id, "go"]].id
    end

    test "ignores databases not in the :uploaded state" do
      # Create a newer database, but is not in the :uploaded state
      create(:codeql_database, repository: @repo, language: "ruby", state: "starter")
      db = CodeqlDatabase.latest_for_repos_and_languages([[@repo.id, "ruby"]])[[@repo.id, "ruby"]]
      refute_nil db
      assert db.created_at <= 1.day.ago
    end

    test "handles and filters out non-existent repos" do
      assert_equal Hash.new, CodeqlDatabase.latest_for_repos_and_languages([[10001, "javascript"]])
    end

    test "handles and filters out invalid languages" do
      assert_equal Hash.new, CodeqlDatabase.latest_for_repos_and_languages([[@repo.id, "rubbish"]])
    end
  end

  context "#latest_database_is_user_uploaded" do
    test "doesn't error on empty list" do
      assert_equal [].to_set, CodeqlDatabase.latest_database_is_user_uploaded([], @code_scanning_app.bot.id)
    end

    test "keeps repo/language only if latest database is not by the code scanning bot" do
      # Create an old database for one language, and a new database for another.
      # Both uploaded by the code scanning bot.
      Timecop.freeze(2.days.ago) do
        create(:codeql_database, repository: @repo, language: "ruby", uploader: @code_scanning_app.bot)
      end
      create(:codeql_database, repository: @repo, language: "go", uploader: @code_scanning_app.bot)

      assert_equal [[@repo.id, "ruby"]].to_set,
        CodeqlDatabase.latest_database_is_user_uploaded([[@repo.id, "ruby"], [@repo.id, "go"]], @code_scanning_app.bot.id)
    end

    test "correctly determines the latest database in the case of conflicting timestamps" do
      # Latest database (one with higher id) is uploaded by bot
      Timecop.freeze(2.hours.ago) do
        create(:codeql_database, repository: @repo, language: "ruby", uploader: @user)
        create(:codeql_database, repository: @repo, language: "ruby", uploader: @code_scanning_app.bot)
      end
      assert_equal [].to_set,
        CodeqlDatabase.latest_database_is_user_uploaded([[@repo.id, "ruby"]], @code_scanning_app.bot.id)

      # Latest database (one with higher id) is uploaded by user
      Timecop.freeze(1.hour.ago) do
        create(:codeql_database, repository: @repo, language: "ruby", uploader: @code_scanning_app.bot)
        create(:codeql_database, repository: @repo, language: "ruby", uploader: @user)
      end
      assert_equal [[@repo.id, "ruby"]].to_set,
        CodeqlDatabase.latest_database_is_user_uploaded([[@repo.id, "ruby"]], @code_scanning_app.bot.id)
    end

    test "ignores databases not in the :uploaded state" do
      create(:codeql_database, repository: @repo, language: "ruby", uploader: @code_scanning_app.bot, state: "starter")
      assert_equal [[@repo.id, "ruby"]].to_set,
        CodeqlDatabase.latest_database_is_user_uploaded([[@repo.id, "ruby"]], @code_scanning_app.bot.id)
    end

    test "handles and filters out non-existent repos" do
      assert_equal [].to_set, CodeqlDatabase.latest_database_is_user_uploaded([[10001, "javascript"]], @code_scanning_app.bot.id)
    end

    test "handles and filters out invalid languages" do
      assert_equal [].to_set, CodeqlDatabase.latest_database_is_user_uploaded([[@repo.id, "rubbish"]], @code_scanning_app.bot.id)
    end
  end

  context "#latest_for_repo/#latest_for_repo_and_language" do
    test "returns all the languages" do
      dbs = CodeqlDatabase.latest_for_repo(@repo.id)
      assert_equal 3, dbs.size
      assert_equal %w[ruby go java].to_set, dbs.map(&:language).to_set
    end

    test "only returns the latest database for each language" do
      newgodb = create(:codeql_database, repository: @repo, language: "go", uploader: @code_scanning_app.bot)

      oldrubydb = Timecop.freeze(1.week.ago) do
        # No effect
        create(:codeql_database, repository: @repo, language: "ruby", uploader: @code_scanning_app.bot)
      end

      dbs = CodeqlDatabase.latest_for_repo(@repo.id)
      assert_equal 3, dbs.size
      assert_equal %w[ruby go java].to_set, dbs.map(&:language).to_set
      refute_equal oldrubydb.id, dbs.find { |db| db.language == "ruby" }.id
      assert_equal newgodb.id, dbs.find { |db| db.language == "go" }.id
    end

    test "if timestamps clash, returns the highest id" do
      newest = Timecop.freeze(1.minute.ago) do
        create(:codeql_database, repository: @repo, language: "cpp", uploader: @code_scanning_app.bot)
        create(:codeql_database, repository: @repo, language: "cpp", uploader: @code_scanning_app.bot)
      end

      cppdbs = CodeqlDatabase.latest_for_repo(@repo.id).select { |db| db.language == "cpp" }
      assert_equal 1, cppdbs.size
      assert_equal newest.id, cppdbs[0].id
    end

    test "Respects language parameter" do
      assert_equal "go", CodeqlDatabase.latest_for_repo_and_language(@repo.id, "go").language
    end
  end

  context "#storage_delete_object_if_exists" do
    test "called when object destroyed" do
      db = CodeqlDatabase.create!(
        repository: @repo, uploader: @repo.owner, state: :uploaded, size: 1234,
        name: "java.zip", content_type: "application/zip", language: "java"
      )

      db.expects(:storage_delete_object_if_exists)
      db.destroy
    end

    # This matters because a failed asset deletion prevents the model from being
    # deleted, so we want asset deletion to succeed even if it's a no-op.
    test "doesn't raise exception if asset not present" do
      db = CodeqlDatabase.create!(
        repository: @repo, uploader: @repo.owner, state: :uploaded, size: 1234,
        name: "java.zip", content_type: "application/zip", language: "java"
      )
      path = "/#{GitHub.codeql_variant_analysis_memory_alpha_bucket}/#{db.storage_s3_key(nil)}"

      assert_nothing_raised do
        # `delete_status: 404` simulates a missing asset.
        assert_storage_policy_delete(db, path, delete_status: 404) do
          db.storage_delete_object_if_exists
        end
      end
    end
  end
end
