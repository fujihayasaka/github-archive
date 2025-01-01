# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodeqlBulkBuilderOnboardJobTest < GitHub::TestCase
  fixtures do
    @repo1 = create(:repository)
    @repo2 = create(:repository)

    @typescript_language_name = create(:language_name, name: "TypeScript")
    @ruby_language_name = create(:language_name, name: "Ruby")
    python_language_name = create(:language_name, name: "Python")
    swift_language_name = create(:language_name, name: "Swift")
    elixir_language_name = create(:language_name, name: "Elixir")
    create(:language, repository: @repo1, language_name: @typescript_language_name)
    create(:language, repository: @repo1, language_name: elixir_language_name)
    create(:language, repository: @repo2, language_name: @ruby_language_name)
    create(:language, repository: @repo2, language_name: python_language_name)
    create(:language, repository: @repo1, language_name: swift_language_name)

    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)
  end

  context "dotcom only", skip_enterprise: true do
    test "does nothing when passed empty list" do
      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [])

      assert_equal 0, CodeqlBulkBuilderConfig.count
    end

    test "onboards repos that are not already onboarded" do
      repos_and_languages = [
        [@repo1.id, "javascript"],
        [@repo2.id, "ruby"],
        [@repo2.id, "python"],
      ]
      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: repos_and_languages)

      assert_equal repos_and_languages.to_set, CodeqlBulkBuilderConfig.all.pluck(:repository_id, :language).to_set
    end

    test "does nothing when repo is already onboarded" do
      create(:codeql_bulk_builder_config, repository: @repo1, language: "javascript")

      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[@repo1.id, "javascript"]])

      assert_equal 1, CodeqlBulkBuilderConfig.count
    end

    test "activates repos that are already onboarded but incative" do
      config = create(:codeql_bulk_builder_config, repository: @repo1, language: "javascript", is_active: false, consecutive_build_failures: 2)

      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[@repo1.id, "javascript"]])

      config.reload
      assert_equal true, config.is_active
      assert_equal 0, config.consecutive_build_failures
    end

    test "does nothing when repo is private" do
      private_repo = create(:private_repository)
      create(:language, repository: private_repo, language_name: @typescript_language_name)

      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[private_repo.id, "javascript"]])

      assert_equal 0, CodeqlBulkBuilderConfig.count
    end

    test "does nothing when language is not supported" do
      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[@repo1.id, "elixir"]])

      assert_equal 0, CodeqlBulkBuilderConfig.count
    end

    test "does nothing when language is not available in repo" do
      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[@repo2.id, "javascript"]])

      assert_equal 0, CodeqlBulkBuilderConfig.count
    end

    test "onboards swift repos when feature flag is disabled" do
      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[@repo1.id, "swift"]])

      assert_equal 1, CodeqlBulkBuilderConfig.count
    end

    test "handles non-existent repos" do
      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[12345, "javascript"]])

      assert_equal 0, CodeqlBulkBuilderConfig.count
    end

    # This is the case for repos that were onboarded to the old bulk-builder config system.
    # Going forward this isn't expected to happen, but if it does the repo should still be onboarded.
    test "onboards repo when it has a bulk-builder-uploaded database, but is not onboarded" do
      create(:codeql_database, repository: @repo1, language: "javascript", uploader: @code_scanning_app.bot)

      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[@repo1.id, "javascript"]])

      assert_equal 1, CodeqlBulkBuilderConfig.count
    end

    test "does nothing when repo has a user-uploaded database" do
      create(:codeql_database, repository: @repo1, language: "javascript", uploader: create(:user))

      CodeqlBulkBuilderOnboardJob.perform_now(repos_and_languages: [[@repo1.id, "javascript"]])

      assert_equal 0, CodeqlBulkBuilderConfig.count
    end
  end
end
