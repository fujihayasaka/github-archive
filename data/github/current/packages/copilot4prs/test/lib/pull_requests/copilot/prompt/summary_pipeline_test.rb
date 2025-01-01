# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestsCopilotPromptSummaryPipelineTest < GitHub::TestCase
  fixtures do
    @org = create(:copilot_for_business_enabled_organization)
    @org_repo = create(:repository, owner: @org, from_example: :pull_request_source)
    @pr_with_ignored_files = create(:pull_request, :with_mergeable_head, repository: @org_repo)
    create(:copilot_content_exclusion_configuration, :organization, resource: @org,
      document: <<~YAML
        "#{GitHub.url}/#{@org_repo.nwo}": ["**/*.txt"]
      YAML
    )
    create(:copilot_content_exclusion_configuration, :repository, resource: @org_repo)

    @repository = create(:repository, from_example: :pull_request_source)
    @pull_request = create(:pull_request, :with_mergeable_head, repository: @repository)
    @overall_completion = "Updates the project to add a new hello world style method."
  end

  setup do
    @pipeline = PullRequests::Copilot::Prompt::SummaryPipeline.new(
      comparison: @pull_request.historical_comparison,
      repository: @repository,
      pull_request: @pull_request
    )
  end

  context "#perform" do
    test "times the perform process form start to finish" do
      stub_copilot_api_calls
      frozen_now = Time.now.utc
      Timecop.freeze frozen_now do
        GitHub.dogstats.expects(:timing_since).at_least_once
        GitHub.dogstats.expects(:timing_since).with("copilot.prompt.summary_pipeline_run", frozen_now, tags: {
          pipeline_class: "pull_requests/copilot/prompt/summary_pipeline"
        })
        @pipeline.perform(@pull_request.user)
      end
    end

    test "times the generation of a completion" do
      stub_copilot_api_calls
      frozen_now = Time.now.utc
      Timecop.freeze frozen_now do
        GitHub.dogstats.expects(:timing_since).at_least_once
        GitHub.dogstats.expects(:timing_since).with("copilot.prompt.create_completion", frozen_now, tags: ["prompt_class:PullRequests::Copilot::Prompt::OverallSummary"]).at_least_once
        @pipeline.perform(@pull_request.user)
      end
    end

    test "runs a series of prompts to get a final response" do
      stub_copilot_api_calls
      assert_equal @overall_completion, @pipeline.perform(@pull_request.user)
    end

    test "stores all prompts and completions" do
      stub_copilot_api_calls
      assert_equal @overall_completion, @pipeline.perform(@pull_request.user)
      assert_equal 1, @pipeline.all_prompts_and_completions.size, "Prompts and completions from each summary stage should be stored"
    end

    test "obeys copilot ignore rules" do
      pipeline = PullRequests::Copilot::Prompt::SummaryPipeline.new(
        comparison: @pr_with_ignored_files.historical_comparison,
        pull_request: @pr_with_ignored_files,
        repository: @org_repo
      )

      stub_copilot_api_calls
      exception = assert_raises PullRequests::Copilot::Prompt::SummaryPipeline::NoMeaningfulFilesError do
        pipeline.perform(@pr_with_ignored_files.user)
      end

      assert_equal "This pull request contains files that could not be processed. Please contact our support team for more details.", exception.message
    end

    test "returns a meaningful error message for pull requests with only empty files" do
      stub_copilot_api_calls
      PullRequests::Copilot::Prompt::OverallSummary.stubs(:prompts).returns([])

      exception = assert_raises PullRequests::Copilot::Prompt::SummaryPipeline::NoMeaningfulFilesError do
        @pipeline.perform(@pull_request.user)
      end

      assert_equal "This pull request contains files that could not be processed. Please contact our support team for more details.", exception.message
    end
  end

  private

  def stub_copilot_api_calls
    Copilot::User::CopilotApi
      .any_instance
      .stubs(:async_create_chat_completion)
      .returns(Promise.new.fulfill({ "choices" => [{ "message" => { "content" => @overall_completion } }] }))
  end

  def build_pretend_diff_hunk(number_of_lines: 1)
    lines = []
    number_of_lines.times { lines << [GitHub::Diff::Line.new(type: :empty, text: "")] }
    PullRequests::Copilot::DiffHunk.new(
      header: GitHub::Diff::Line.new(type: :empty, text: ""),
      lines:,
      entry: GitHub::Diff::Entry.new("", "")
    )
  end
end
