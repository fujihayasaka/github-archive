# typed: true
# frozen_string_literal: true

require "test_helper"

class CodeqlBulkBuilderConfigTest < GitHub::TestCase
  context "#update_last_updated" do
    test "Doesn't crash when called on invalid data" do
      CodeqlBulkBuilderConfig.update_last_updated([
        [999, "javascript"],
        [1234, "something"],
        [8657845, ""],
      ])
    end

    test "Updates exactly the configs it is called on" do
      repos = 3.times.map { create(:repository) }
      Timecop.freeze(1.day.ago) do
        @config1 = create(:codeql_bulk_builder_config, repository: repos[0], language: "javascript")
        @config2 = create(:codeql_bulk_builder_config, repository: repos[0], language: "ruby")
        @config3 = create(:codeql_bulk_builder_config, repository: repos[1], language: "cpp")
        @config4 = create(:codeql_bulk_builder_config, repository: repos[1], language: "csharp")
        @config5 = create(:codeql_bulk_builder_config, repository: repos[2], language: "java")
        @config6 = create(:codeql_bulk_builder_config, repository: repos[2], language: "go")
        @config7 = create(:codeql_bulk_builder_config, repository: repos[2], language: "swift")
      end
      initial_last_attempted = @config1.last_attempted

      CodeqlBulkBuilderConfig.update_last_updated([
        [@config1.repository_id, @config1.language],
        [@config2.repository_id, @config2.language],
        [@config3.repository_id, @config3.language],
      ])

      assert initial_last_attempted < @config1.reload.last_attempted
      assert initial_last_attempted < @config2.reload.last_attempted
      assert initial_last_attempted < @config3.reload.last_attempted

      assert_equal initial_last_attempted, @config4.reload.last_attempted
      assert_equal initial_last_attempted, @config5.reload.last_attempted
      assert_equal initial_last_attempted, @config6.reload.last_attempted
      assert_equal initial_last_attempted, @config7.reload.last_attempted
    end
  end

  context "#not_onboarded" do
    test "only returns repo/language pairs that have not been onboarded" do
      repo1 = create(:repository)
      repo2 = create(:repository)
      create(:codeql_bulk_builder_config, repository: repo1, language: "javascript")
      assert_equal [[repo1.id, "python"], [repo2.id, "cpp"]].to_set,
        CodeqlBulkBuilderConfig.not_onboarded([[repo1.id, "javascript"], [repo1.id, "python"], [repo2.id, "cpp"]])
    end
  end
end
