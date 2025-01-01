# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodeqlBulkBuilderOffboardJobTest < GitHub::TestCase
  fixtures do
    @repo1 = create(:repository)
    @repo1_javascript = create(:codeql_bulk_builder_config, repository: @repo1, language: "javascript")
    @repo1_ruby = create(:codeql_bulk_builder_config, repository: @repo1, language: "ruby")
    @repo2 = create(:repository)
    @repo2_javascript = create(:codeql_bulk_builder_config, repository: @repo2, language: "javascript")
  end

  context "dotcom only", skip_enterprise: true do
    test "does nothing when passed empty list" do
      CodeqlBulkBuilderOffboardJob.perform_now(repos_and_languages: [])

      assert_equal 3, CodeqlBulkBuilderConfig.count
    end

    test "offboards repos that are currently onboarded" do
      repos_and_languages = [
        [@repo1.id, "javascript"],
        [@repo2.id, "javascript"],
        [@repo2.id, "ruby"],
      ]
      CodeqlBulkBuilderOffboardJob.perform_now(repos_and_languages: repos_and_languages)

      assert_equal 1, CodeqlBulkBuilderConfig.count
      assert_equal @repo1_ruby.id, T.must(CodeqlBulkBuilderConfig.first).id
    end

    test "does nothing when repo is not onboarded" do
      CodeqlBulkBuilderOffboardJob.perform_now(repos_and_languages: [[@repo1.id, "cpp"]])

      assert_equal 3, CodeqlBulkBuilderConfig.count
    end

    test "handles non-existent repos" do
      CodeqlBulkBuilderOffboardJob.perform_now(repos_and_languages: [[12345, "javascript"]])

      assert_equal 3, CodeqlBulkBuilderConfig.count
    end
  end
end
