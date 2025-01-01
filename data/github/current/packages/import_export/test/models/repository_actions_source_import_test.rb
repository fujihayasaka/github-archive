# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryActionsSourceImportTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repository = create(:repository, owner: @user)
  end

  setup do
    GitHub.stubs(:git_src_migrator_url).returns("http://gsm.localhost:4567/twirp")
    GitHub.stubs(:git_src_migrator_staging_url).returns("http://gsm-staging.localhost:4567/twirp")
    GitHub.stubs(:git_src_migrator_review_lab_url).returns("http://gsm-review-lab.localhost:4567/twirp")

    GitSrcMigrator::Twirp::MigrationClient.any_instance.stubs(:start_migration)
    GitSrcMigrator::Twirp::MigrationClient.any_instance.stubs(:get_migration)

    @import = RepositoryActionsSourceImport.new(user: @user, repository: @repository)

    GitHub.flipper[:import_export_gitops_on_actions_use_staging].disable
    GitHub.flipper[:import_export_gitops_on_actions_use_review_lab].disable
  end

  context "#start_import" do
    test "calls GitSrcMigrator::Twirp::MigrationClient#start_migration with expected parameters" do
      GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:start_migration).with(
        source_url: "https://github.com/example-org/example-repo.git",
        source_type: :SOURCE_TYPE_SOURCE_IMPORT,
        source_access_token: "testtoken",
        repository_id: @repository.id,
        target_owner_id: @repository.owner.id,
        target_ssh_url: @repository.ssh_url,
        source_username: "monalisa",
        user_id: @user.id
      )

      @import.start_import(
        source_url: "https://github.com/example-org/example-repo.git",
        source_username: "monalisa",
        source_access_token: "testtoken"
      )
    end

    test "returns response from GitSrcMigrator::Twirp::MigrationClient#start_migration" do
      start_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#start_migration")
      GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:start_migration).returns(start_migration_mock)

      assert_equal @import.start_import(source_url: "https://github.com/example-org/example-repo.git"), start_migration_mock
    end

    context "when import_export_gitops_on_actions_use_staging is disabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for prod" do
        GitHub.flipper[:import_export_gitops_on_actions_use_staging].disable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        start_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#start_migration")
        migration_client_mock.expects(:start_migration).returns(start_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.start_import(source_url: "https://github.com/example-org/example-repo.git"), start_migration_mock
      end
    end

    context "when import_export_gitops_on_actions_use_staging is enabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for staging" do
        GitHub.flipper[:import_export_gitops_on_actions_use_staging].enable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_staging_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        start_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#start_migration")
        migration_client_mock.expects(:start_migration).returns(start_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.start_import(source_url: "https://github.com/example-org/example-repo.git"), start_migration_mock
      end
    end

    context "when import_export_gitops_on_actions_use_review_lab is disabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for prod" do
        GitHub.flipper[:import_export_gitops_on_actions_use_review_lab].disable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        start_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#start_migration")
        migration_client_mock.expects(:start_migration).returns(start_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.start_import(source_url: "https://github.com/example-org/example-repo.git"), start_migration_mock
      end
    end

    context "when import_export_gitops_on_actions_use_review_lab is enabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for review lab" do
        GitHub.flipper[:import_export_gitops_on_actions_use_review_lab].enable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_review_lab_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        start_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#start_migration")
        migration_client_mock.expects(:start_migration).returns(start_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.start_import(source_url: "https://github.com/example-org/example-repo.git"), start_migration_mock
      end
    end

    context "when both import_export_gitops_on_actions_use_staging and import_export_gitops_on_actions_use_review_lab are enabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for staging" do
        GitHub.flipper[:import_export_gitops_on_actions_use_staging].enable
        GitHub.flipper[:import_export_gitops_on_actions_use_review_lab].enable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_staging_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        start_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#start_migration")
        migration_client_mock.expects(:start_migration).returns(start_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.start_import(source_url: "https://github.com/example-org/example-repo.git"), start_migration_mock
      end
    end

    context "when source_access_token and source_username are nil" do
      test "calls GitSrcMigrator::Twirp::MigrationClient#start_migration with expected parameters" do
        GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:start_migration).with(
          source_url: "https://github.com/example-org/example-repo.git",
          source_type: :SOURCE_TYPE_SOURCE_IMPORT,
          source_access_token: nil,
          repository_id: @repository.id,
          target_owner_id: @repository.owner.id,
          target_ssh_url: @repository.ssh_url,
          source_username: nil,
          user_id: @user.id
        )

        @import.start_import(
          source_url: "https://github.com/example-org/example-repo.git",
          source_username: nil,
          source_access_token: nil
        )
      end
    end

    context "when the source_access_token and source_username parameters are not passed" do
      test "calls GitSrcMigrator::Twirp::MigrationClient#start_migration with expected parameters" do
        GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:start_migration).with(
          source_url: "https://github.com/example-org/example-repo.git",
          source_type: :SOURCE_TYPE_SOURCE_IMPORT,
          source_access_token: nil,
          repository_id: @repository.id,
          target_owner_id: @repository.owner.id,
          target_ssh_url: @repository.ssh_url,
          source_username: nil,
          user_id: @user.id
        )

        @import.start_import(source_url: "https://github.com/example-org/example-repo.git")
      end
    end

    context "when GitSrcMigrator::Twirp::MigrationClient#start_migration returns an error" do
      test "raises a GitSrcMigrator::Twirp::Error error" do
        error = GitSrcMigrator::Twirp::Error.new("example error")
        GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:start_migration).raises(error)

        assert_raises(GitSrcMigrator::Twirp::Error, "example_error") do
          @import.start_import(source_url: "https://github.com/example-org/example-repo.git")
        end
      end
    end
  end

  context "#status" do
    test "calls GitSrcMigrator::Twirp::MigrationClient#get_migration with expected parameters" do
      GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:get_migration).with(repository_id: @repository.id)

      @import.status
    end

    test "returns response from GitSrcMigrator::Twirp::MigrationClient#get_migration" do
      get_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#get_migration")
      GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:get_migration).returns(get_migration_mock)

      assert_equal @import.status, get_migration_mock
    end

    context "when import_export_gitops_on_actions_use_staging is disabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for prod" do
        GitHub.flipper[:import_export_gitops_on_actions_use_staging].disable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        get_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#get_migration")
        migration_client_mock.expects(:get_migration).returns(get_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.status, get_migration_mock
      end
    end

    context "when import_export_gitops_on_actions_use_staging is enabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for staging" do
        GitHub.flipper[:import_export_gitops_on_actions_use_staging].enable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_staging_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        get_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#get_migration")
        migration_client_mock.expects(:get_migration).returns(get_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.status, get_migration_mock
      end
    end

    context "when import_export_gitops_on_actions_use_review_lab is disabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for prod" do
        GitHub.flipper[:import_export_gitops_on_actions_use_review_lab].disable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        get_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#get_migration")
        migration_client_mock.expects(:get_migration).returns(get_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.status, get_migration_mock
      end
    end

    context "when import_export_gitops_on_actions_use_review_lab is enabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for review lab" do
        GitHub.flipper[:import_export_gitops_on_actions_use_review_lab].enable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_review_lab_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        get_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#get_migration")
        migration_client_mock.expects(:get_migration).returns(get_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.status, get_migration_mock
      end
    end

    context "when both import_export_gitops_on_actions_use_staging and import_export_gitops_on_actions_use_review_lab are enabled" do
      test "uses a GitSrcMigrator::Twirp::MigrationClient instance configured for staging" do
        GitHub.flipper[:import_export_gitops_on_actions_use_staging].enable
        GitHub.flipper[:import_export_gitops_on_actions_use_review_lab].enable

        migration_client_expectation = GitSrcMigrator::Twirp::MigrationClient.expects(:new).with do |params|
          assert_equal params[:faraday_connection].url_prefix.to_s, GitHub.git_src_migrator_staging_url
        end

        migration_client_mock = mock("GitSrcMigrator::Twirp::MigrationClient")
        get_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#get_migration")
        migration_client_mock.expects(:get_migration).returns(get_migration_mock)
        migration_client_expectation.returns(migration_client_mock)

        assert_equal @import.status, get_migration_mock
      end
    end

    context "when GitSrcMigrator::Twirp::MigrationClient#get_migration returns an error" do
      test "raises a GitSrcMigrator::Twirp::Error error" do
        error = GitSrcMigrator::Twirp::Error.new("example error")
        GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:get_migration).raises(error)

        assert_raises(GitSrcMigrator::Twirp::Error, "example_error") { @import.status }
      end
    end
  end

  context "#migration_exists?" do
    test "calls GitSrcMigrator::Twirp::MigrationClient#get_migration with expected parameters" do
      GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:get_migration).with(repository_id: @repository.id)

      @import.migration_exists?
    end

    test "returns response from GitSrcMigrator::Twirp::MigrationClient#get_migration" do
      get_migration_mock = mock("GitSrcMigrator::Twirp::MigrationClient#get_migration")
      GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:get_migration).returns(get_migration_mock)

      assert @import.migration_exists?
    end

    context "when GitSrcMigrator::Twirp::MigrationClient#get_migration returns an error" do
      test "raises a GitSrcMigrator::Twirp::Error error" do
        error = GitSrcMigrator::Twirp::Error.new("example error")
        GitSrcMigrator::Twirp::MigrationClient.any_instance.expects(:get_migration).raises(error)

        refute @import.migration_exists?
      end
    end
  end
end
