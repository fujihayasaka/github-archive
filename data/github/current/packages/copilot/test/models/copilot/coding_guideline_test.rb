# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::CodingGuidelineTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
    @guideline = create(:copilot_coding_guideline, repository: @repo)
    @path = create(:copilot_coding_guideline_path, copilot_coding_guideline: @guideline, path: "path/to/file1")
  end

  context "#to_copilot_reference" do
    test "returns correct hash with file patterns included by default" do
      result = @guideline.to_copilot_reference
      expected = {
        type: "github.coding_guideline",
        id: "#{@repo.name_with_display_owner}-#{@guideline.id}",
        data: {
          id: @guideline.id,
          type: "coding-guideline",
          repositoryId: @repo.id,
          name: @guideline.name,
          description: @guideline.description,
          filePatterns: [@path.path]
        }
      }

      assert_equal expected, result
    end

    test "returns correct hash with empty file patterns when exclude_file_patterns is true" do
      result = @guideline.to_copilot_reference(exclude_file_patterns: true)
      expected = {
        type: "github.coding_guideline",
        id: "#{@repo.name_with_display_owner}-#{@guideline.id}",
        data: {
          id: @guideline.id,
          type: "coding-guideline",
          repositoryId: @repo.id,
          name: @guideline.name,
          description: @guideline.description,
          filePatterns: []
        }
      }

      assert_equal expected, result
    end
  end

  context "on create" do
    test "it enables the guideline by default" do
      # we are counting the `@guideline` fixture above
      Copilot::CodingGuideline.stub_const(:MAX_ENABLED_PER_REPO, 2) do
        guideline = create(:copilot_coding_guideline, repository: @repo)
        assert_predicate guideline, :enabled?
      end
    end

    test "it disables the guideline if the repository has exceeded the limit" do
      # we are counting the `@guideline` fixture above
      Copilot::CodingGuideline.stub_const(:MAX_ENABLED_PER_REPO, 1) do
        guideline = create(:copilot_coding_guideline, repository: @repo)
        refute_predicate guideline, :enabled?
      end
    end

    test "it does not allow creating more than MAX_PER_REPO guidelines for a repository" do
      Copilot::CodingGuideline.stub_const(:MAX_PER_REPO, 1) do
        assert_no_changes -> { Copilot::CodingGuideline.count } do
          assert_raises_with_message(
            ActiveRecord::RecordInvalid,
            "Validation failed: cannot create more than 1 guidelines for a repository",
          ) do
            create(:copilot_coding_guideline, repository: @repo)
          end
        end
      end
    end
  end
end
