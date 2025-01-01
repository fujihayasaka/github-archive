# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeqlBulkBuilderDependencyTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)
  end

  context "#languages_onboarded_for_codeql_bulk_building" do
    test "returns an empty array when no languages onboarded" do
      assert_equal [], @repo.languages_onboarded_for_codeql_bulk_building
    end

    test "returns only the languages onboarded for this repo" do
      another_repo = create(:repository, owner: @user)

      create(:codeql_bulk_builder_config, repository: @repo, language: "java")
      create(:codeql_bulk_builder_config, repository: @repo, language: "python")
      create(:codeql_bulk_builder_config, repository: another_repo, language: "go")

      assert_equal %w[java python], @repo.languages_onboarded_for_codeql_bulk_building
    end
  end

  context "#onboard_language_for_codeql_bulk_building" do
    test "returns true for a new language" do
      assert_equal true, @repo.onboard_language_for_codeql_bulk_building("java")
      assert_equal ["java"], @repo.languages_onboarded_for_codeql_bulk_building
    end

    test "returns false when the language is already onboarded" do
      create(:codeql_bulk_builder_config, repository: @repo, language: "java")
      assert_equal false, @repo.onboard_language_for_codeql_bulk_building("java")
      assert_equal ["java"], @repo.languages_onboarded_for_codeql_bulk_building
    end

    test "throws an error for an invalid language" do
      assert_raises(ActiveRecord::RecordInvalid) do
        @repo.onboard_language_for_codeql_bulk_building("something")
      end
      assert_equal [], @repo.languages_onboarded_for_codeql_bulk_building
    end
  end

  context "#offboard_language_from_codeql_bulk_building" do
    test "returns true for a language that was onboarded" do
      create(:codeql_bulk_builder_config, repository: @repo, language: "java")
      create(:codeql_bulk_builder_config, repository: @repo, language: "python")
      assert_equal true, @repo.offboard_language_from_codeql_bulk_building("java")
      assert_equal ["python"], @repo.languages_onboarded_for_codeql_bulk_building
    end

    test "returns false for a language that was not onboarded" do
      create(:codeql_bulk_builder_config, repository: @repo, language: "python")
      assert_equal false, @repo.offboard_language_from_codeql_bulk_building("java")
      assert_equal ["python"], @repo.languages_onboarded_for_codeql_bulk_building
    end
  end
end
