# typed: strict
# frozen_string_literal: true

module TriageAgent
  module Configuration
    CONFIG_FILE_PATH = T.let(".github/issues/triage-agent.md".freeze, String)

    # Legacy template used when new_config feature flag is disabled.
    LEGACY_CONFIGURATION_TEMPLATE = T.let(<<~MARKDOWN.freeze, String)
      ### Coding agent suitability

      In addition to normal triage, assess whether the issue is suitable for automated coding agent assignment.

      Issues are suitable when they have:

      - Clear, specific requirements
      - Sufficient context and details
      - Well-defined success criteria
      - Self-contained scope

      Issues are not suitable when they require:

      - Investigation or research
      - Design decisions or approvals
      - Extensive coordination
      - Policy or architectural choices

      Record your assessment in the triage comment using this format:

      | Aspect | Recommendation | Rationale |
      | :---- | :---- | :---- |
      | 🤖 **Coding agent suitability** | [Suitable/Needs more info/Not suitable] | [why] |

      ### Additional instructions
      <!-- You can provide any additional instructions to instruct the Triage agent. -->
    MARKDOWN

    # New template used when new_config feature flag is enabled.
    BASIC_CONFIGURATION_TEMPLATE = T.let(<<~MARKDOWN.freeze, String)
      ---
      on:
        issue-create: true
        issue-comment: true
      allowed-actions:
        add-comment: true
        add-labels:
          allowed: ["*"]
        add-type:
          allowed: ["*"]
        add-fields:
          allowed: ["*"]
      ---

      You are an issue triage agent. Analyze this issue, categorize it with the right metadata, and surface similar past issues to help maintainers act quickly.

      ## Guidelines

      - Do not apply metadata to incomplete or low-quality issues (spam, gibberish, test issues). Flag them in the report instead.
      - Do not overwrite existing issue type or field values already set on the issue.
      - Only set fields when you can confidently determine the value from the issue content.
      - Assess coding agent suitability (Suitable / Needs more info / Not suitable).

      ### Additional instructions
      <!-- You can provide any additional instructions to instruct the Triage agent. -->

    MARKDOWN

    # Returns the appropriate configuration template based on the feature flag.
    #
    # @param repository [Repository, nil] The repository to check the feature flag for
    # @return [String] The configuration template
    sig { params(repository: T.nilable(Repository)).returns(String) }
    def self.basic_configuration_template(repository: nil)
      if repository && IssuesTriageAgentFeature.new_config_enabled?(repository)
        BASIC_CONFIGURATION_TEMPLATE
      else
        LEGACY_CONFIGURATION_TEMPLATE
      end
    end

    # Returns the default prompt text (markdown body without frontmatter).
    sig { params(repository: T.nilable(Repository)).returns(String) }
    def self.default_prompt(repository: nil)
      template = basic_configuration_template(repository: repository)
      # Strip frontmatter if present
      if template.start_with?("---\n")
        _frontmatter, body = template.split(/^---\n/, 3)[1..2]
        (body || "").strip
      else
        template.strip
      end
    end

    # Legacy sidebar docs used when new_config feature flag is disabled.
    LEGACY_SIDEBAR_DOCS = T.let(<<~MARKDOWN.freeze, String)
      # Triage Agent Configuration

      The Triage Agent analyzes new issues and provides triage comments with recommendations. The agent's behavior is influenced through this configuration file, while core functionality is managed by the system.

      ## What the agent does (system-managed)

      The agent automatically:
      - Analyzes issue title, description, and referenced content
      - Provides structured triage reports with assessment rationale in the comments
      - Flags low-quality or spam issues
      - Applies relevant issue types, labels, and issue field values

      **Triage agent cannot:** edit issue titles/bodies, close issues, assign users, or modify milestones/projects.

      ## Configuring label and Issue field restrictions (optional)

      By default, the agent can apply any repository label, type, or field. Use the front matter to optionally restrict which labels and fields the agent can **automatically apply**.

      **Label restrictions** (choose one approach):
      ```
      allowed_labels: ["bug", "enhancement", "question"]
      ```
      or
      ```
      disallowed_labels: ["wontfix", "duplicate"]
      ```

      **Field restrictions** (choose one approach):
      ```
      allowed_fields: ["Priority", "Component"]
      ```
      or
      ```
      disallowed_fields: ["Internal-Only"]
      ```

      The agent can always **suggest** any repository label or field in comments, but will only **automatically apply** items from the allowed list (or not in the disallowed list). If no restrictions are configured, any repository label/field can be applied.

      ## Customization options

      In your configuration file, you can:
      - **Exclusion rules**: Skip certain issue types or labels (e.g., Task, Epic)
      - **Triage criteria**: Define how to evaluate type, priority, and labels
      - **Repository instructions**: Add label definitions, priority criteria, domain-specific rules
      - **File references**: Point to CONTRIBUTING.md, issue templates, or other docs

      ## Getting started

      1. Create `.github/issues/triage-agent.md` in your repository
      2. Optionally customize exclusions, criteria, and repository-specific instructions
      3. Optionally configure `allowed_labels` or `disallowed_labels` if label restrictions are needed
      4. Enable the agent: Issues > Triage Agent > Start the agent
      5. Test with sample issues and refine

      Enable/disable anytime via the Issues page control menu.
    MARKDOWN

    # New sidebar docs used when new_config feature flag is enabled.
    SIDEBAR_DOCS = T.let(<<~MARKDOWN.freeze, String)
      # Triage Agent Configuration

      The Triage Agent runs automatically when new issues are added to the repository, analyzing them and providing triage recommendations. It can also be invoked manually by users with the Triage role or higher by mentioning Copilot in issue comments (e.g. "@copilot retriage this issue").
      Configure it by editing this file.

      ## File structure

      The config uses **YAML frontmatter** for structured settings and **markdown body** for triage instructions.

      ## `on` (required)

      Specifies which events trigger the triage agent. Both triggers must be present.

      ```yaml
      ---
      on:
        issue-create: true        # required — true or { filter: "<query>" }
        issue-comment: true       # required — true or false
      ---
      ```

      **Triggers:**
      - `issue-create` — triggers on new issues. Supports an optional `filter` to limit which issues are triaged.
      - `issue-comment` — triggers retriage when someone mentions `@copilot` in a comment. Set to `true` or `false`.

      **Rules:**
      - `on` is required — config is invalid without it
      - Both `issue-create` and `issue-comment` are required

      ## `allowed-actions` (required)

      Controls which actions the agent can take. All action keys are required.

      ```yaml
      ---
      allowed-actions:
        add-comment: true         # Required: true/false
        add-labels:
          allowed: [values...]    # Permitted values
          blocked: [values...]    # Blocked values
        add-type:
          allowed: ["*"]          # Allow all types
        add-fields:
          blocked: [Priority]     # Block specific fields
      ---
      ```

      Use `allowed-actions: ["*"]` to allow everything.

      **Rules:**
      - All four keys (`add-comment`, `add-labels`, `add-type`, `add-fields`) are required
      - `add-comment` is a boolean (true/false) — controls whether the agent posts a triage comment
      - `blocked` takes precedence over `allowed`
      - Use `["*"]` as wildcard for all values

      ## `filter` (scoped per trigger)

      When set, only issues matching the query are triaged — all other issues are skipped. This helps save PRU costs by focusing triage on the issues that matter. Uses [GitHub Issues advanced search syntax](https://docs\.github\.com/en/issues/tracking-your-work-with-issues/using-issues/filtering-and-searching-issues-and-pull-requests#building-advanced-filters-for-issues).

      **Example — only triage issues labeled `bug` or `enhancement`:**

      ```yaml
      on:
        issue-create:
          filter: "label:bug OR label:enhancement"
      ```

      **Example — only triage unassigned issues without a milestone:**

      ```yaml
      on:
        issue-create:
          filter: "no:assignee no:milestone"
      ```

      If `filter` is omitted, every new issue is triaged.

      ## Triage instructions (markdown body)

      The markdown below the frontmatter tells the agent how to triage. Customize the steps to match your team's workflow.

      ## Cost

      Each triage run consumes **1 PRU** (Premium Request Unit).
    MARKDOWN

    # Returns the appropriate sidebar docs based on the feature flag.
    #
    # @param repository [Repository, nil] The repository to check the feature flag for
    # @return [String] The sidebar docs markdown
    sig { params(repository: T.nilable(Repository)).returns(String) }
    def self.sidebar_docs(repository: nil)
      if repository && IssuesTriageAgentFeature.new_config_enabled?(repository)
        SIDEBAR_DOCS
      else
        LEGACY_SIDEBAR_DOCS
      end
    end

    # Reads the triage agent configuration from the repository's .github/issues/triage-agent.md file.
    #
    # @param repository [Repository] The repository to read triage agent configuration from
    # @return [String] The triage agent configuration content
    sig { params(repository: Repository).returns(T.nilable(String)) }
    def self.read_triage_agent_configuration(repository)
      default_branch_ref = repository.default_branch_ref
      unless default_branch_ref
        return nil
      end

      blob = repository.blob(default_branch_ref.target_oid, CONFIG_FILE_PATH)
      data = blob&.data
      data
    end
  end
end
