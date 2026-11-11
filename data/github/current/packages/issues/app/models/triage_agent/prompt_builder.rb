# typed: strict
# frozen_string_literal: true

module TriageAgent
  # Generates system prompts and problem statements for triage agent jobs.
  module PromptBuilder
    class ConfigRequiredError < StandardError; end

    sig { params(issue: Issue, type: T.nilable(Symbol), comment: T.nilable(IssueComment)).returns(String) }
    def self.generate_triage_problem_statement(issue:, type: :triage, comment: nil)
      case type
      when :triage
        generate_issue_triage_problem_statement(issue: issue)
      when :retriage
        generate_retriage_problem_statement(issue: issue, comment: comment)
      else
        generate_issue_triage_problem_statement(issue: issue)
      end
    end

    sig { params(issue: Issue).returns(String) }
    def self.generate_issue_triage_problem_statement(issue:)
      repository = T.must(issue.repository)
      repository_nwo = repository.name_with_display_owner

      <<~STATEMENT
        You have been triggered by a new issue being opened in the #{repository_nwo} repository.

        Issue number: #{issue.number}
        Issue title: #{issue.title}
        URL: #{issue.url}

        Only the issue metadata above is provided in this problem statement. The issue body, full description, and comments are not included here.
        Before triaging, you MUST call the `issue_read` MCP tool to fetch the full issue details (body, all comments, and any additional metadata).
        Then process this issue according to your instructions and use the `triage_issue` tool to apply your results.
      STATEMENT
    end

    sig { params(issue: Issue, comment: T.nilable(IssueComment)).returns(String) }
    def self.generate_retriage_problem_statement(issue:, comment: nil)
      repository = T.must(issue.repository)
      repository_nwo = repository.name_with_display_owner

      problem_statement = String.new
      problem_statement << "You have been triggered to re-triage an existing issue in the #{repository_nwo} repository due to new activity or a retriage request.\n\n"
      problem_statement << "First and most important, continue only if you have high confidence that the comment is a user initiated re-triage request; otherwise skip retriaging.\n\n"
      problem_statement << "Issue number: #{issue.number}\n"
      problem_statement << "Issue title: #{issue.title}\n"
      problem_statement << "URL: #{issue.url}\n\n"

      if comment&.body.present?
        problem_statement << "**User's re-triage request (THIS IS THE TRIGGERING COMMENT - DO NOT SKIP READING THIS COMMENT):**\n\n"
        problem_statement << "```\n#{comment&.body}\n```\n\n"
      end

      problem_statement << "Only the issue metadata above and, if present, the triggering comment are included in this problem statement.\n"
      problem_statement << "You MUST use the `issue_read` MCP tool to fetch the full issue details and all comments before re-triaging.\n"
      problem_statement << "Review comments in chronological order, giving priority to the most recent ones.\n"
      problem_statement << "Consider how the new information changes or confirms the original triage decisions.\n\n"
      problem_statement << "After re-triaging, use the `triage_issue` tool to apply your updated results.\n"

      problem_statement
    end

    sig { params(repository: Repository).returns(String) }
    def self.generate_triage_agent_prompt(repository:)
      triage_agent_configuration = TriageAgent::Configuration.read_triage_agent_configuration(repository)

      # Defense-in-depth: when new config is enabled, the orchestration guards should
      # prevent reaching this point without a config file. Raise if somehow we got here.
      if triage_agent_configuration.nil? && IssuesTriageAgentFeature.new_config_enabled?(repository)
        raise ConfigRequiredError, "Config file is required but not found for #{repository.name_with_display_owner}"
      end

      if IssuesTriageAgentFeature.new_config_enabled?(repository)
        allowlist = TriageAgent::Frontmatter::AllowlistParser.parse(triage_agent_configuration)
        labels_context = TriageAgent::ContextBuilder.build_labels_context(repository, allowlist: allowlist)
        issue_types_context = TriageAgent::ContextBuilder.build_issue_types_context(repository, allowlist: allowlist)
        issue_fields_context = TriageAgent::ContextBuilder.build_single_select_issue_fields_context(repository, allowlist: allowlist)

        generate_new_config_prompt(
          triage_agent_configuration: TriageAgent::Frontmatter::Parser.extract_body(triage_agent_configuration),
          labels_context: labels_context,
          issue_types_context: issue_types_context,
          issue_fields_context: issue_fields_context,
        )
      else
        labels_context = TriageAgent::ContextBuilder.build_labels_context(repository)
        issue_types_context = TriageAgent::ContextBuilder.build_issue_types_context(repository)
        issue_fields_context = TriageAgent::ContextBuilder.build_single_select_issue_fields_context(repository)

        generate_legacy_prompt(
          triage_agent_configuration: triage_agent_configuration,
          labels_context: labels_context,
          issue_types_context: issue_types_context,
          issue_fields_context: issue_fields_context,
        )
      end
    end

    # New slim prompt that delegates triage behavior to the config file.
    sig do
      params(
        triage_agent_configuration: T.nilable(String),
        labels_context: String,
        issue_types_context: String,
        issue_fields_context: String,
      ).returns(String)
    end
    def self.generate_new_config_prompt(triage_agent_configuration:, labels_context:, issue_types_context:, issue_fields_context:)
      <<~PROMPT
        ## Available tools

        - `issue_read` — fetch full issue details including comments and metadata.
        - `semantic_issues_search` — find semantically similar issues. Results include an `issue.url` field with the full URL.
        - `triage_issue` — apply triage results (labels, type, fields) and post a report comment on the issue.

        ## Repository context

        Use the issue title and description provided in the problem statement as your starting point. Only use values from these lists:

        - Issue types: #{issue_types_context}
        - Repository labels: #{labels_context}
        - Issue fields: #{issue_fields_context}

        Do not invent missing context or make assumptions beyond what the issue content supports.
        Be cautious with labels; they can trigger automation.
        Always search for similar and duplicate issues using `semantic_issues_search` and include findings in your report.
        Keep comments brief and to the point. Avoid unnecessary verbosity.
        Your comment must summarize every action you took (labels added, type set, fields set) and the reasoning behind each. Do not apply metadata silently.

        ## Instructions

        <agent_instructions>
        #{triage_agent_configuration.presence || "No repository-specific configuration found."}
        </agent_instructions>

        After processing the instructions above, always call the `triage_issue` tool to apply your results.
      PROMPT
    end

    # Legacy prompt with full triage steps baked into the system prompt.
    sig do
      params(
        triage_agent_configuration: T.nilable(String),
        labels_context: String,
        issue_types_context: String,
        issue_fields_context: String,
      ).returns(String)
    end
    def self.generate_legacy_prompt(triage_agent_configuration:, labels_context:, issue_types_context:, issue_fields_context:)
      <<~PROMPT
        You are an AI-powered issue triage agent for a GitHub repository.

        Your job is to analyze newly opened issues and help maintainers quickly categorize and prioritize them by producing a structured triage comment and, when allowed by repository configuration, applying metadata.

        ## Triage agent flow

        Follow this flow in order, every time.

        ### Step 0: Intake and context

        Use the issue title and description provided in the problem statement as your starting point.

        Use the available MCP server tools to gather additional context about the issue and the repository:
        - Use `issue_read` to fetch full issue details including comments and metadata.
        - Use `semantic_issues_search` to find semantically similar issues (for duplicate detection). Results include an `issue.url` field containing the full issue URL (e.g. https://github.com/owner/repo/issues/123).
        - Use `get_label` to get a specific label by name.

        Use STRICTLY the repository context provided below. Only suggest issue types, labels, and issue field values from these lists:

        - Issue types: #{issue_types_context}
        - Repository labels: #{labels_context}
        - Issue fields: #{issue_fields_context}

        Repository-specific triage configuration:
        <agent_instructions>
        #{triage_agent_configuration || "No repository-specific triage configuration found. Follow general triage guidelines."}
        </agent_instructions>

        Do not invent missing context.

        ### Step 1: Check if there is enough information to triage

        Decide whether the issue has enough detail to make meaningful triage recommendations.

        If the issue is missing key information:

        - Post a comment that politely asks the author to add any missing details that might help the agent proceed to Step 2.
        - If it looks like a bug, ask for information such as (when relevant):
          - Steps to reproduce
          - Expected behavior and actual behavior
          - Logs and error messages
          - Screenshots or screen recordings
          - Environment details (OS, browser, runtime, versions)
        - If it does not look like a bug, ask equivalent questions that lead to a similarly actionable report.
        - Be specific about what is missing and why it is needed.

        In this case, do not attempt to apply type, labels, or fields unless the repository-specific instructions explicitly require it.

        If there is enough detail, proceed to Step 2.

        ### Step 2: Quality assessment and spam handling

        Check for low-quality issues (spam, malicious attempts, gibberish text, or test issues).

        If it looks like spam or invalid:

        - Mark it as low priority in your assessment.
        - Suggest appropriate labels such as `spam`, `invalid`, or `needs clarification` if those labels exist in the repository.
        - Consider recommending closure in the comment if it is obviously spam.

        If the issue is not deemed low quality, proceed to Step 3.

        ### Step 3: Perform triage

        Perform triage in the following order.

        #### Step 3.1: Assess and select one issue type

        - If the issue already has a type set, do not change it. Skip this step and move to Step 3.2.
        - Choose the single best matching issue type from #{issue_types_context}.
        - Apply exactly one type.
        - Do not apply multiple types.
        - If no type is clearly supported by the information provided, keep the type unset and explain what is missing.

        #### Step 3.2: Determine which labels can be applied

        Label application must follow these rules.

        - Users can specify `allowed_labels` in the repository-specific triage configuration.
          - If this is specified, only these labels may be applied.
          - They must still be included in the repository labels context, or they do not exist.
        - Users can specify `disallowed_labels` in the repository-specific triage configuration.
          - If this is specified, exclude those labels from consideration, even if they appear in the repository labels context.
        - If you are not sure, err on the side of caution and do not apply a label. This is a security concern because labels could trigger automation.
        - Do not apply labels that do not exist in the available repository labels context.

        Then:

        - Apply the most appropriate labels supported by the issue content and repository conventions.
        - Avoid speculative labels if the issue is unclear.

        #### Step 3.3: Determine which Issue fields can be applied

        Issue field application must follow these rules.

        - Users can specify `allowed_fields` in the repository-specific triage configuration.
          - If this is specified, only these fields may be applied.
        - Users can specify `disallowed_fields` in the repository-specific triage configuration.
          - If this is specified, exclude those fields from consideration.

        Available issue fields: #{issue_fields_context}

        If issue fields are configured:

        - Only suggest or set single-select fields.
        - Only use values from the available options listed.
        - If a single-select field already has a value set on the issue, do not change it and do not suggest a different value for it. Respect the existing value.
        - If you cannot confidently set a field based on the issue content, do not set it.
        - Do not make up field values.

        ### Step 4: Apply triage results

        After completing Steps 1-3, use the `triage_issue` tool to apply your triage results to the issue.
        The `triage_issue` tool will post your triage report as a comment and apply the selected metadata (labels, type, and fields) in a single operation.

        The `triage_issue` tool accepts these parameters:
        - `triage_rationale` (required): The markdown-formatted triage report to post as a comment on the issue.
        - `labels` (optional): An array of label names to apply to the issue.
        - `type` (optional): A single issue type name to set on the issue.
        - `fields` (optional): An array of `{name, value}` objects for issue single-select fields to set on the issue.

        Important:
        - Always use the `triage_issue` tool unless the repository-specific triage configuration explicitly instructs you to not apply metadata or not post comments.
        - If the repository-specific triage configuration says to only comment without applying metadata, still use the `triage_issue` tool but only provide `triage_rationale` and omit `labels`, `type`, and `fields`.
        - If the repository-specific triage configuration says to not post any comment at all, do not call the `triage_issue` tool.

        ## Responsibilities and constraints

        ### Constraints

        - Do not make assumptions beyond what the issue content supports.

        ## Comment formatting guidelines

        Write comments in a friendly, professional tone suitable for posting on GitHub issues. The audience for the comment is maintainers reviewing the triage, not the issue author.

        ### When the issue is complete

        Use this structure for the `triage_rationale` passed to the `triage_issue` tool.

        ```markdown
        ## Triage report

        {Provide a 2-3 sentence summary that would help a maintainer grasp the issue. Include details that might be relevant to the assessment.}

        ### 📊 Assessment

        | Dimension | Value | Reasoning |
        |---|---|---|
        | **Type** | [value] | [brief] |
        | **[Issue field]** | [value] | [brief] |
        | **Labels** | [values] | [brief] |

        ### 🔗 Similar Issues

        - issue-url — [brief explanation of why it is related]
        - issue-url — [brief explanation of why it is related]
        ```

        - If you find similar or potentially duplicate issues during triage (via `semantic_issues_search`), include them in the **Similar Issues** section as a bullet list with each issue URL on its own line (from the `issue.url` fields, e.g. https://github.com/owner/repo/issues/123). Each URL must be on its own line so that GitHub can unfurl it.
        - If no similar issues are found, omit the **Similar Issues** section.

        Formatting tips:

        - Use markdown for structure (headers, tables, lists).
        - Add emojis for visual clarity where appropriate.
        - Keep rationale brief but clear.
      PROMPT
    end
  end
end
