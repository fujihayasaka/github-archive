# typed: strict
# frozen_string_literal: true

# SummaryPipeline
# ===================
# The summary pipeline is instantiated and called from PullRequests::Copilot::GenerateDiffSummaryJob in order to
# summarize the contents of a pull request using the copilot API. The pipeline uses GPT4 in a single step
# summarization approach where diffhunks from the PR are used to generate an overall summary of the PR.
#
# The resulting completion returned from the copilot API has additional processing applied to it in order to provide
# links to diffs on the files tab for a given PR. First, we decode the references generated during the
# "summarize diffhunks" step back out into links to the diffhunks themselves. Then we parse through the text and
# clean up these links for easier reading such that the file name at the start of a change description becomes a
# link, and subsequent references in a given change description just have reference numbers, like [1] [2] [3].
#
# Finally, we return the content to the front end which is poling for the PullRequests::Copilot::GenerateDiffSummaryJob
# status. On the front end the diffhunk links we've built in the pipeline are translated into links to the files tab
# via the HTML pipeline. This last step can't be done in the job because it is possible that a user is generating a
# summary for some diffhunks that are not in a PR yet as they're still writing the description before creating it.
module PullRequests
  module Copilot
    module Prompt
      class SummaryPipeline
        include DiffHunkEncoder
        include SummaryPipelineHelper

        sig { returns(GitHub::Comparison) }
        attr_reader :comparison

        sig { returns(Repository) }
        attr_reader :repository

        sig { override.returns(T.nilable(PullRequest)) }
        attr_reader :pull_request

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        attr_reader :all_prompts_and_completions

        MAX_CONCURRENCY = CopilotAPI::MAX_CONCURRENCY

        class NoMeaningfulFilesError < StandardError; end
        class RetriesExceededError < StandardError; end
        class EmptyResponseError < StandardError; end

        sig do
          params(
            comparison: GitHub::Comparison,
            repository: Repository,
            pull_request: T.nilable(PullRequest),
          ).void
        end
        def initialize(comparison:, repository:, pull_request: nil)
          @comparison = comparison
          @repository = repository
          @pull_request = pull_request
          @all_prompts_and_completions = T.let([], T::Array[T::Hash[Symbol, String]])
        end

        sig do
          params(
            actor: User,
            token: T.nilable(T.any(::Copilot::DecryptedToken, ::Copilot::EncryptedToken))
          ).returns(String)
        end
        def perform(actor, token: nil)
          start_time = Time.current

          target = repository.fork? ? repository.parent || repository : repository
          owner = target.owner
          copilot_content_exclusion_rules = nil
          #  need to fetch the copilot ignore list
          if owner.is_a?(Organization) && ::Copilot::ContentExclusion.is_available?(owner)
            paths = ::Copilot::ContentExclusion.rules_for_repo(target).flat_map { |_config, rules| rules.collect(&:patterns).flatten.uniq }
            copilot_content_exclusion_rules = paths.map { |path| path[0] == "/" ? path[1..-1] : path }
          end

          filtered_diffs = PullRequests::Copilot::DiffsFilter.new(diffs: comparison.diffs, copilot_content_exclusion: copilot_content_exclusion_rules).to_a
          if filtered_diffs.empty?
            raise NoMeaningfulFilesError.new("This pull request contains files that could not be processed. Please contact our support team for more details.")
          end

          diff_hunks = PullRequests::Copilot::DiffHunk.diffs_to_hunks(filtered_diffs)
          overall_summary_prompt = OverallSummary.prompts(diff_hunks:, pull_request:).first
          if overall_summary_prompt.nil?
            raise NoMeaningfulFilesError.new("This pull request contains files that could not be processed. Please contact our support team for more details.")
          end

          begin
            overall_completion = completion(overall_summary_prompt, actor, token)
          rescue CopilotAPI::RateLimitError => e
            raise RetriesExceededError.new("Error: This pull request could not be processed due to rate limiting.")
          end

          overall_completion = overall_summary_prompt.references.decode_and_expand_all(overall_completion)
          overall_completion = simplify_diffhunk_links(overall_completion)

          GitHub.dogstats.timing_since(
            "copilot.prompt.summary_pipeline_run",
            start_time,
            tags: { pipeline_class: T.must(self.class.name).underscore.downcase }
          )
          overall_completion
        end

        private

        sig do
          params(
            prompt: PullRequests::Copilot::Prompt::OverallSummary,
            actor: User,
            token: T.nilable(T.any(::Copilot::DecryptedToken, ::Copilot::EncryptedToken))
          ).returns(String)
        end
        def completion(prompt, actor, token)
          start_time = Time.current
          rendered_prompt = prompt.render # rendering generates the messages as well

          model_version = actor.feature_enabled?(:use_gpt_4o_upgrade) ? "gpt-4o-2024-11-20" : "gpt-4o-2024-05-13"
          result = actor.copilot_api(integration_id: CopilotAPI::COPILOT_4_PRS_INTEGRATION_ID, token: token).async_create_chat_completion(
            model: model_version,
            messages: prompt.messages.map(&:to_h),
            max_tokens: prompt.expected_response_tokens.max,
            temperature: 0.4,
            stop: prompt.stops.presence || []
          ).then do |completion|
            choices = completion["choices"]
            unless choices && choices.first["message"]["content"]
              raise EmptyResponseError.new("Received empty response")
            end
            choices.first["message"]["content"].strip
          end.sync
          @all_prompts_and_completions << { prompt: rendered_prompt, completion: result }

          GitHub.dogstats.timing_since("copilot.prompt.create_completion", start_time, tags: ["prompt_class:#{prompt.class.name}"])
          result
        end
      end
    end
  end
end
