# typed: true
# frozen_string_literal: true

require "test_helper"

class WorkspaceEditor::DiffAnalysisClientTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository, from_example: :review_comment_fork)
    @pull =
      create(:pull_request,
        repository: @repo,
        base_repository: @repo,
        base_user: @repo.owner,
        base_ref: "master",
        head_ref: "topic",
        issue: create(:issue, repository: @repo),
      )
  end

  setup do
    skip if GitHub.enterprise?
    User.any_instance.stubs(:workspace_editor_preview_enabled?).returns(true)
  end

  test "returns diff information" do
    client = WorkspaceEditor::DiffAnalysisClient.new(pull_request: @pull, current_user: @pull.user)
    DiffAnalysis::V1::DiffAnalysisServiceClient.any_instance.stubs(:analyze_diff).with do |request|
      assert_instance_of DiffAnalysis::V1::AnalyzeDiffRequest, request

      assert_equal 3, request.files.size
      assert_equal "aquaman.txt", request.files[0].path
      assert_equal "file11", request.files[1].path
      assert_equal "file18", request.files[2].path
      assert_equal :MODIFIED, request.files[0].change_type
      assert_equal :ADDED, request.files[1].change_type
      assert_equal :ADDED, request.files[2].change_type

      assert_equal false, request.categorize
      assert_equal false, request.detect_patch_risk
    end.returns(MockResponse.new)

    client.analyze_diff
  end

  class MockResponse
    def initialize(data = nil)
      @data = data
    end

    attr_reader :data
  end
end
