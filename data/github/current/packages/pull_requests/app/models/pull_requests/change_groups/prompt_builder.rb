# typed: strict
# frozen_string_literal: true

module PullRequests
  module ChangeGroups
    class PromptBuilder
      PROMPT_MAX_ISSUE_BODY_LENGTH = 16_700 # P99 value for issue body character length, ~4175 tokens
      # LLMs aren't good at counting things, so apply some padding to our
      # enforced maximum length to allow the model to significantly over-shoot
      # the requested limit.
      PROMPT_MAX_NAME_LENGTH = 20
      PROMPT_MAX_NUMBER_OF_GROUPS = 10

      OUTPUT_JSON_SCHEMA = T.let({
        type: "object",
        properties: {
          semanticGroups: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: {
                  type: "string",
                  description: "Short, descriptive name for a group of related changes (e.g., 'User authentication', 'Performance optimization'). Maximum length of #{PROMPT_MAX_NAME_LENGTH} characters."
                },
                hunkIds: {
                  type: "array",
                  items: { type: "integer" },
                  description: "Array of hunk IDs that belong to this semantic group. Only include IDs that exist in the provided hunks."
                },
                priority: {
                  type: "integer",
                  minimum: 0,
                  maximum: 10,
                  description: "Rate how urgently a human reviewer should read this group first. 0 = cosmetic / trivial changes, 10 = critical business logic or security-sensitive change"
                },
                bugRisk: {
                  type: "integer",
                  minimum: 0,
                  maximum: 10,
                  description: "Estimate the likelihood these changes introduce a defect, considering algorithmic complexity, use of low-level APIs, widespread refactor, etc."
                },
                confidence: {
                  type: "integer",
                  minimum: 0,
                  maximum: 10,
                  description: "Rate your confidence in your own understanding of this group's intent. Provide 0 when diff is extremely terse or ambiguous."
                }
              },
              required: %w[name hunkIds priority bugRisk confidence],
            }
          },
        },
        required: %w[semanticGroups],
        additionalProperties: false,
        description: <<~DESC
          Group the hunks into semantic categories based on their functional purpose.
          - Focus on the intent behind changes rather than file location.
          - Prioritize important functional changes over minor or cosmetic updates.
          - Ensure every hunkID provided to you is included in one or more groups.
        DESC
      }.freeze, T::Hash[Symbol, T.anything])

      class Result < T::Struct
        const :system_prompt, String
        const :user_prompt, String

        sig { returns(T::Array[{ role: String, content: String }]) }
        def messages
          [
            { role: "developer", content: system_prompt },
            { role: "user", content: user_prompt },
          ]
        end

        sig { returns(Integer) }
        def total_length
          user_prompt.length + system_prompt.length
        end

        sig { returns(T::Hash[Symbol, T.anything]) }
        def expected_response_schema = OUTPUT_JSON_SCHEMA
      end

      sig do
        params(
          pull_request: PullRequest,
          diff_hunks_by_id: T::Hash[Integer, Copilot::DiffHunk],
          issues: T::Array[Issue],
        ).void
      end
      def initialize(pull_request:, diff_hunks_by_id:, issues:)
        @pull_request = pull_request
        @diff_hunks_by_id = diff_hunks_by_id
        @issues = issues
      end

      sig { returns(Result) }
      def build
        Result.new(system_prompt:, user_prompt:)
      end

      private

      sig { returns(String) }
      def system_prompt
        instructions = [
          "- Create groups based on their purpose. The most important groups should come first.",
          "- When possible, use groups to separate signal from noise. For example, if a PR contains a lot of refactoring, you can use groups to separate the refactoring from the new features.",
          "- Keep group size to a minimum, but don't split up important related changes",
        ]

        if FeatureFlag.vexi.enabled?(:pull_requests_limit_change_groups_prompt, @pull_request.user, default: false)
          instructions << "- Keep the total number of groups under #{PROMPT_MAX_NUMBER_OF_GROUPS}"
        end

        instructions += [
          "- Hunks can only belong to one group.",
          "- Only include hunkIds that appear in the Hunks list; if none apply, return an empty array.",
          "- Keep group names short, maximum #{PROMPT_MAX_NAME_LENGTH} characters.",
        ]

        <<~PROMPT
          You are an AI assistant that helps code reviewers review pull requests by breaking the changes into smaller groups that are easier to review. Your response will be used to build a new code review UI where reviewers step through each group and see the hunks in context.

          Instructions:
          #{instructions.join("\n          ")}

          JSON schema:

          #{JSON.pretty_generate(OUTPUT_JSON_SCHEMA)}

          You MUST answer with a JSON object that matches the JSON schema above.
        PROMPT
      end

      sig { returns(String) }
      def user_prompt
        <<~PROMPT
          Analyze this pull request and generate semantic groups according to the schema:

          ## Pull request
          Title: #{@pull_request.title} (##{@pull_request.number})
          Description: #{@pull_request.body}

          ## Related issues
          The following issues are related to this pull request. Use this to improve your understanding of the changes:
          #{issues_prompt}

          ## Hunks
          The following hunks (grouped by file) are available for you to reference in your semanticGroups:
          #{hunks_prompt}
        PROMPT
      end

      sig { returns(String) }
      def issues_prompt
        if @issues.empty?
          "No related issues found."
        else
          issue_prompts = @issues.map do |issue|
            <<~ISSUE
              #{issue.title} (##{issue.number})
              #{issue.body&.truncate(PROMPT_MAX_ISSUE_BODY_LENGTH)}
              ---
            ISSUE
          end
          issue_prompts.join("\n\n")
        end
      end

      sig { returns(String) }
      def hunks_prompt
        hunks_by_path = {}

        @diff_hunks_by_id.each do |id, hunk|
          hunks_by_path[hunk.file_path] ||= {
            modificationType: hunk.entry.status_label,
            hunks: [],
          }
          hunks_by_path[hunk.file_path][:hunks] << {
            hunkId: id,
            snippet: hunk.diff_text_without_line_numbers,
          }
        end

        JSON.pretty_generate(hunks_by_path)
      end
    end
  end
end
