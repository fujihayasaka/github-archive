# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests::Copilot
  class ReviewBodyMessageGeneratorTest < GitHub::TestCase
    def setup
      @pull = PullRequest.new
      @pull.stubs(:changed_files).returns(5)
      @repo = create(:repository)
      @comments = []
      @summary = {}
      @summary[:short] = { overall_summary: "Overall summary", per_file_summary: "| File | Description |
| ---- | ----------- |
| file1 | description |" }
      @summary[:medium] = { overall_summary: "Overall summary", per_file_summary: "| File | Description |
| ---- | ----------- |
| file1 | description |
| file2 | description |
| fileN | description |" }
      @summary[:long] = { overall_summary: "Overall summary", per_file_summary: "| File | Description |
| ---- | ----------- |
| file1 | description |
| file2 | description |
| file3 | description |
| file4 | description |
| file5 | description |
| file6 | description |" }
      @model_response = {}

      @summary.each do |type, summary|
        @model_response["#{type}_summary"] = {
          copilot_references: [
            { type: "github.pull-request-summary", data: summary },
            { type: "github.excluded-pull-request-comment", data: { path: "file1.rb", line: 10, body: "Comment body", line_content: "line content" } },
            { type: "github.excluded-file", data: { file_path: "file2.rb", language: "Ruby", reason: "file_type_not_supported" } }
          ]
        }
        @requestor = User.new
        @requestor.stubs(:feature_enabled?).returns(true)
      end
    end


    test "with empty line_content inside comment body" do
      model_response = {
        copilot_references: [
          { type: "github.excluded-pull-request-comment", data: { path: "main.rb", line: 10, body: "this line is missing a nil check", line_content: "" } },
        ]
      }
      generator = ReviewBodyMessageGenerator.new(pull: @pull, repo: @repo, comments: @comments, model_response: model_response, requestor: @requestor)
      assert_not_match /.*#{<<~EMPTY_CODEBLOCK}/, generator.create
      ```

      ```
      EMPTY_CODEBLOCK
    end

    test "with short summary" do
      generator = ReviewBodyMessageGenerator.new(pull: @pull, repo: @repo, comments: @comments, model_response: @model_response["short_summary"], requestor: @requestor)
      comment = generator.create
      assert_match /## Pull Request Overview.*#{Regexp.escape(@summary[:short][:overall_summary])}.*/m, comment
      refute_match /### Reviewed Changes/, comment
    end

    test "with medium summary" do
      generator = ReviewBodyMessageGenerator.new(pull: @pull, repo: @repo, comments: @comments, model_response: @model_response["medium_summary"], requestor: @requestor)
      assert_match /## Pull Request Overview.*#{Regexp.escape(@summary[:medium][:overall_summary])}.*?### Reviewed Changes.*?Copilot reviewed 4 out of 5 changed files in this pull request and generated no comments..*?#{Regexp.escape(@summary[:medium][:per_file_summary])}.*?/m, generator.create
    end

    test "with long summary" do
      generator = ReviewBodyMessageGenerator.new(pull: @pull, repo: @repo, comments: @comments, model_response: @model_response["long_summary"], requestor: @requestor)
      assert_match /## Pull Request Overview.*#{Regexp.escape(@summary[:long][:overall_summary])}.*?### Reviewed Changes.*?Copilot reviewed 4 out of 5 changed files in this pull request and generated no comments..*?<details>.*?<summary>Show a summary per file<\/summary>.*?#{Regexp.escape(@summary[:long][:per_file_summary].gsub("\n", "\r\n"))}.*?<\/details>.*?/m, generator.create
    end
  end
end
