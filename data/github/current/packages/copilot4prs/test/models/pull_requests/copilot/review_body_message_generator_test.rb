# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests::Copilot
  class ReviewBodyMessageGeneratorTest < GitHub::TestCase
    def setup
      @pull = PullRequest.new
      @pull.stubs(:changed_files).returns(5)
      @repo = Repository.new
      @comments = []
      @model_response = {
        copilot_references: [
          { type: "github.excluded-pull-request-comment", data: { path: "file1.rb", line: 10, body: "Comment body", line_content: "line content" } },
          { type: "github.excluded-file", data: { file_path: "file2.rb", language: "Ruby", reason: "file_type_not_supported" } }
        ]
      }
      @requestor = User.new
      @requestor.stubs(:feature_enabled?).returns(true)
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
  end
end
