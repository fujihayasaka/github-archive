# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestsCopilotPromptSummaryPipelineHelperTest < GitHub::TestCase
  class TestPipeline
    include PullRequests::Copilot::Prompt::SummaryPipelineHelper
  end

  setup do
    @pipeline = TestPipeline.new
  end

  context "#simplify_diffhunk_links" do
    test "replaces single references with a diffhunk link for the file name at the start of the line" do
      initial_completion = <<~INPUT
        This PR makes good changes. The best changes. Even `Gemfile` changes.

        * `Gemfile`: Added dependencies to the `Gemfile` for the Sinatra app to enable database management and server configuration. ([`Gemfile`](diffhunk://#diff-d09ea66f8227784ff4393d88a19836f321c915ae10031d16c93d67e6283ab55fR1-R8))
        * `config/database.yml`: Added a development database configuration using SQLite3 to `config/database.yml` ([`config/database.yml`](diffhunk://#diff-5a674c769541a71f2471a45c0e9dde911b4455344e3131bddc5a363701ba6325R1-R3)).
        * I googled a lot of questions I had <a href="https://www.google.com/search?q=google">like this</a>
        * `README.md`: Added local development instructions. ([`README.md`](diffhunk://#diff-b335630551682c19a781afebcf4d07bf978fb1f8ac04c6bf87428ed5106870f5L1-R6))
      INPUT

      expected_result = <<~EXPECTED
        This PR makes good changes. The best changes. Even `Gemfile` changes.

        * [`Gemfile`](diffhunk://#diff-d09ea66f8227784ff4393d88a19836f321c915ae10031d16c93d67e6283ab55fR1-R8): Added dependencies to the `Gemfile` for the Sinatra app to enable database management and server configuration.
        * [`config/database.yml`](diffhunk://#diff-5a674c769541a71f2471a45c0e9dde911b4455344e3131bddc5a363701ba6325R1-R3): Added a development database configuration using SQLite3 to `config/database.yml`.
        * I googled a lot of questions I had <a href="https://www.google.com/search?q=google">like this</a>
        * [`README.md`](diffhunk://#diff-b335630551682c19a781afebcf4d07bf978fb1f8ac04c6bf87428ed5106870f5L1-R6): Added local development instructions.
      EXPECTED

      assert_equal expected_result, @pipeline.simplify_diffhunk_links(initial_completion)
    end

    test "changes the link text in multiple diffhunk refrence links into numbers" do
      initial_completion = <<~INPUT
        This PR makes good changes. The best changes. Even `Gemfile` changes.

        * `packages/pull_requests/app/lib/pull_requests/copilot/prompt/summary_pipeline.rb`: Updated `SummaryPipeline` class to iterate through `hunk_summary_prompts` and call `decode_and_expand_all` on `overall_completion` for each prompt, and added new method `simplify_diffhunk_links`. ([packages/pull_requests/app/lib/pull_requests/copilot/prompt/summary_pipeline.rbL71-R81](diffhunk://#diff-fcc71c57fddce344eed1ad26cfe2e8c5ced165815a7d05f9af826098abc62e8bL71-R81), [packages/pull_requests/app/lib/pull_requests/copilot/prompt/summary_pipeline.rbR183-R201](diffhunk://#diff-fcc71c57fddce344eed1ad26cfe2e8c5ced165815a7d05f9af826098abc62e8bR183-R201))
        * `packages/pull_requests/app/lib/pull_requests/copilot/prompt/summarize_file_template.text.erb`: Modified `summarize_file_template.text.erb` file to clarify that the summary of changes should include proper inline code references and always end with encoded references in parentheses. ([packages/pull_requests/app/lib/pull_requests/copilot/prompt/summarize_file_template.text.erbL23](diffhunk://#diff-6507e32dbe6f11b09f954836b36bfbd6dc090d2f8ac77ec8bd9bbf085ef42b71L9-R9))
        * `packages/pull_requests/test/lib/pull_requests/copilot/prompt/summary_pipeline_test.rb`: Added tests for `simplify_diffhunk_links` method in `PullRequestsCopilotPromptSummaryPipelineTest` and removed an empty line in `perform` method test. ([packages/pull_requests/test/lib/pull_requests/copilot/prompt/summary_pipeline_test.rbR97-R138](diffhunk://#diff-b1a84fb9043e573a39235df4e34350ec6265e52d9616238f33e262f2d9e7f55dR97-R138), [packages/pull_requests/test/lib/pull_requests/copilot/prompt/summary_pipeline_test.rbL23](diffhunk://#diff-b1a84fb9043e573a39235df4e34350ec6265e52d9616238f33e262f2d9e7f55dL23))
        * `db/migrate/01_create_users.rb`, `db/migrate/02_create_posts.rb`: Created migrations for the User and Post models. ([db/migrate/01_create_users.rbR1-R8](diffhunk://#diff-5d4286a0748ae65eeedc24b11dfb9494a9c973f2e31c5e72b07ea01290af79e6R1-R8), [db/migrate/02_create_posts.rbR1-R10](diffhunk://#diff-b2e5c6f527404f2eeb4a7080600a4d378c4216755c13e4523e56e8609f782818R1-R10))
      INPUT

      expected_result = <<~EXPECTED
        This PR makes good changes. The best changes. Even `Gemfile` changes.

        * [`packages/pull_requests/app/lib/pull_requests/copilot/prompt/summary_pipeline.rb`](diffhunk://#diff-fcc71c57fddce344eed1ad26cfe2e8c5ced165815a7d05f9af826098abc62e8bL71-R81): Updated `SummaryPipeline` class to iterate through `hunk_summary_prompts` and call `decode_and_expand_all` on `overall_completion` for each prompt, and added new method `simplify_diffhunk_links`. [[1]](diffhunk://#diff-fcc71c57fddce344eed1ad26cfe2e8c5ced165815a7d05f9af826098abc62e8bL71-R81) [[2]](diffhunk://#diff-fcc71c57fddce344eed1ad26cfe2e8c5ced165815a7d05f9af826098abc62e8bR183-R201)
        * [`packages/pull_requests/app/lib/pull_requests/copilot/prompt/summarize_file_template.text.erb`](diffhunk://#diff-6507e32dbe6f11b09f954836b36bfbd6dc090d2f8ac77ec8bd9bbf085ef42b71L9-R9): Modified `summarize_file_template.text.erb` file to clarify that the summary of changes should include proper inline code references and always end with encoded references in parentheses.
        * [`packages/pull_requests/test/lib/pull_requests/copilot/prompt/summary_pipeline_test.rb`](diffhunk://#diff-b1a84fb9043e573a39235df4e34350ec6265e52d9616238f33e262f2d9e7f55dR97-R138): Added tests for `simplify_diffhunk_links` method in `PullRequestsCopilotPromptSummaryPipelineTest` and removed an empty line in `perform` method test. [[1]](diffhunk://#diff-b1a84fb9043e573a39235df4e34350ec6265e52d9616238f33e262f2d9e7f55dR97-R138) [[2]](diffhunk://#diff-b1a84fb9043e573a39235df4e34350ec6265e52d9616238f33e262f2d9e7f55dL23)
        * `db/migrate/01_create_users.rb`, `db/migrate/02_create_posts.rb`: Created migrations for the User and Post models. [[1]](diffhunk://#diff-5d4286a0748ae65eeedc24b11dfb9494a9c973f2e31c5e72b07ea01290af79e6R1-R8) [[2]](diffhunk://#diff-b2e5c6f527404f2eeb4a7080600a4d378c4216755c13e4523e56e8609f782818R1-R10)
      EXPECTED

      assert_equal expected_result, @pipeline.simplify_diffhunk_links(initial_completion)
    end

    test "doesn't mess up multiple change descriptions with the same file name" do
      initial_completion = <<~INPUT
        This pull request to `packages/pull_requests` includes changes that aim to simplify the codebase and improve the testing of the `SummaryPipeline` class. The most important changes include removing the `MAX_CONCURRENCY` constant from the `SummaryPipeline` class, updating the `perform` and `batch_completions` methods in the `SummaryPipeline` class, and modifying the `PullRequestsCopilotPromptV1SummaryPipelineTest` class to reflect these changes.

        Codebase simplification:

        * `packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rb`: Removed the `MAX_CONCURRENCY` constant and added a `max_concurrency` method that returns `CopilotAPI::MAX_CONCURRENCY`. ([packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rbL22-L23](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2L22-L23), [packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rbR189-R193](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2R189-R193))
        * `packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rb`: Updated the `perform` method to cast `diff_hunk_summaries` and `file_summaries_by_prompt` to specific types and replaced `summaries_by_entry` with `file_summaries_by_entry`. ([packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rbL57-R70](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2L57-R70))
        * `packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rb`: Modified the `batch_completions` method to accept an array of `SummarizeDiffHunks` or `SummarizeFile` prompts and return a hash mapping these prompts to their completions. Also, replaced `MAX_CONCURRENCY` with the `max_concurrency` method. ([packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rbL138-R150](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2L138-R150))

        Improvements to testing:

        * `packages/pull_requests/test/lib/pull_requests/copilot/prompt/v1/summary_pipeline_test.rb`: Updated the `PullRequestsCopilotPromptV1SummaryPipelineTest` class to reflect the changes in the `SummaryPipeline` class. This includes modifying the expected timing tags in the `GitHub.dogstats` method, adding a new context for the `#batch_completions` method, and updating the `stub_successful_pipeline` method. ([packages/pull_requests/test/lib/pull_requests/copilot/prompt/v1/summary_pipeline_test.rbR36-R38](diffhunk://#diff-453b5c4bb511880919fc8f9a52a0d3f2523f1b6928f8324ef9241b4b47221ee6L38-R38), [packages/pull_requests/test/lib/pull_requests/copilot/prompt/v1/summary_pipeline_test.rbR57-R74](diffhunk://#diff-453b5c4bb511880919fc8f9a52a0d3f2523f1b6928f8324ef9241b4b47221ee6R57-R74), [packages/pull_requests/test/lib/pull_requests/copilot/prompt/v1/summary_pipeline_test.rbL102-R110](diffhunk://#diff-453b5c4bb511880919fc8f9a52a0d3f2523f1b6928f8324ef9241b4b47221ee6L102-R110)
      INPUT

      expected_result = <<~EXPECTED
        This pull request to `packages/pull_requests` includes changes that aim to simplify the codebase and improve the testing of the `SummaryPipeline` class. The most important changes include removing the `MAX_CONCURRENCY` constant from the `SummaryPipeline` class, updating the `perform` and `batch_completions` methods in the `SummaryPipeline` class, and modifying the `PullRequestsCopilotPromptV1SummaryPipelineTest` class to reflect these changes.

        Codebase simplification:

        * [`packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rb`](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2L22-L23): Removed the `MAX_CONCURRENCY` constant and added a `max_concurrency` method that returns `CopilotAPI::MAX_CONCURRENCY`. [[1]](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2L22-L23) [[2]](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2R189-R193)
        * [`packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rb`](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2L57-R70): Updated the `perform` method to cast `diff_hunk_summaries` and `file_summaries_by_prompt` to specific types and replaced `summaries_by_entry` with `file_summaries_by_entry`.
        * [`packages/pull_requests/app/lib/pull_requests/copilot/prompt/v1/summary_pipeline.rb`](diffhunk://#diff-8096514e0cf62bce079cc39be6f1060e5b48d2e021903652812b7d2995f656e2L138-R150): Modified the `batch_completions` method to accept an array of `SummarizeDiffHunks` or `SummarizeFile` prompts and return a hash mapping these prompts to their completions. Also, replaced `MAX_CONCURRENCY` with the `max_concurrency` method.

        Improvements to testing:

        * [`packages/pull_requests/test/lib/pull_requests/copilot/prompt/v1/summary_pipeline_test.rb`](diffhunk://#diff-453b5c4bb511880919fc8f9a52a0d3f2523f1b6928f8324ef9241b4b47221ee6L38-R38): Updated the `PullRequestsCopilotPromptV1SummaryPipelineTest` class to reflect the changes in the `SummaryPipeline` class. This includes modifying the expected timing tags in the `GitHub.dogstats` method, adding a new context for the `#batch_completions` method, and updating the `stub_successful_pipeline` method. [[1]](diffhunk://#diff-453b5c4bb511880919fc8f9a52a0d3f2523f1b6928f8324ef9241b4b47221ee6L38-R38) [[2]](diffhunk://#diff-453b5c4bb511880919fc8f9a52a0d3f2523f1b6928f8324ef9241b4b47221ee6R57-R74) [[3]](diffhunk://#diff-453b5c4bb511880919fc8f9a52a0d3f2523f1b6928f8324ef9241b4b47221ee6L102-R110)
      EXPECTED

      assert_equal expected_result, @pipeline.simplify_diffhunk_links(initial_completion)
    end

    test "works on file names with spaces" do
      initial_completion = <<~INPUT
        This PR makes good changes. The best changes. Even `Gemfile` changes.

        * `Gemfile`: Added dependencies to the `Gemfile` for the Sinatra app to enable `:development` database management and server configuration. ([`Gemfile`](diffhunk://#diff-d09ea66f8227784ff4393d88a19836f321c915ae10031d16c93d67e6283ab55fR1-R8))
        * `config/my database.yml`: Added a development database configuration using SQLite3 to `config/my database.yml` ([`config/my database.yml`](diffhunk://#diff-5a674c769541a71f2471a45c0e9dde911b4455344e3131bddc5a363701ba6325R1-R3)).
        * I googled a lot of questions I had <a href="https://www.google.com/search?q=google">like this</a>
        * `README.md`: Added local development instructions. ([`README.md`](diffhunk://#diff-b335630551682c19a781afebcf4d07bf978fb1f8ac04c6bf87428ed5106870f5L1-R6))
      INPUT

      expected_result = <<~EXPECTED
        This PR makes good changes. The best changes. Even `Gemfile` changes.

        * [`Gemfile`](diffhunk://#diff-d09ea66f8227784ff4393d88a19836f321c915ae10031d16c93d67e6283ab55fR1-R8): Added dependencies to the `Gemfile` for the Sinatra app to enable `:development` database management and server configuration.
        * [`config/my database.yml`](diffhunk://#diff-5a674c769541a71f2471a45c0e9dde911b4455344e3131bddc5a363701ba6325R1-R3): Added a development database configuration using SQLite3 to `config/my database.yml`.
        * I googled a lot of questions I had <a href="https://www.google.com/search?q=google">like this</a>
        * [`README.md`](diffhunk://#diff-b335630551682c19a781afebcf4d07bf978fb1f8ac04c6bf87428ed5106870f5L1-R6): Added local development instructions.
      EXPECTED

      assert_equal expected_result, @pipeline.simplify_diffhunk_links(initial_completion)
    end
  end
end
