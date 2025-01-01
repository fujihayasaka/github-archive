# typed: strict
# frozen_string_literal: true

# Helper methods for creating Copilot SWE Agent job
# Based on https://github.com/github/sweagentd/blob/main/internal/problemstatement/issue.go
# Used by Issues::Domain::Copilot#trigger_copilot_job for assigning Copilot across different repos
#
# This helper filters comments in the problem statement to exclude:
# - Minimized/hidden comments
# - Comments from users without write access to the target repository
# This matches the filtering behavior implemented in sweagentd for security and content quality.
module CopilotSweAgentJobHelper
  # Constants for limits and formatting
  MAX_TRUNCATED_COMMENT_BODY_LENGTH = 2000
  MAX_PROBLEM_STATEMENT_BASE64_LENGTH = 40_000 # ~30,000 characters
  SECTION_SEPARATOR = "----\n"
  ISSUE_SECTION_HEADER = "*This section details on the original issue you should resolve*"
  ISSUE_COMMENTS_HEADING = "## Comments on the Issue (you are @copilot in this section)\n"
  TIMEOUT_ERROR_CLASSES = [::Timeout::Error, Faraday::TimeoutError].freeze
  TIMEOUT_ERROR_PATTERNS = /execution expired|Net::ReadTimeout|Faraday::Timeout/i

  # Main entry point
  #
  # Params:
  # - issue:   an Issue object
  # - agent_instructions: optional instruction for the agent/subagent
  # - target_repository: optional target repository for checking write access (defaults to issue's repository)
  #
  # Returns: problem statement string (XML-like, markdown)
  sig { params(issue: Issue, agent_instructions: T.nilable(String), target_repository: T.nilable(Repository)).returns(String) }
  def self.generate_issue_problem_statement(issue:, agent_instructions: nil, target_repository: nil)
    # Filter comments to exclude minimized comments and comments from users without write access
    all_comments = issue.comments.sort_by(&:created_at)
    repository = target_repository || T.must(issue.repository)
    comments = filter_comments_for_problem_statement(all_comments, repository)

    statement = build_statement(issue, comments, agent_instructions, 0, 0)
    return statement if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH

    # Truncate comments, if needed
    statement = build_statement(issue, comments, agent_instructions, 0, MAX_TRUNCATED_COMMENT_BODY_LENGTH)
    return statement if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH

    # Remove oldest comments one by one if still too large
    truncated_comments = comments.dup
    while truncated_comments.any?
      truncated_comments.shift
      statement = build_statement(issue, truncated_comments, agent_instructions, 0, MAX_TRUNCATED_COMMENT_BODY_LENGTH)
      return statement if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
    end

    # Truncate issue body as a last resort
    max_body_length = approximate_max_truncated_issue_body_length(issue, agent_instructions)
    while max_body_length > 0
      statement = build_statement(issue, [], agent_instructions, max_body_length, MAX_TRUNCATED_COMMENT_BODY_LENGTH)
      return statement if base64_length(statement) <= MAX_PROBLEM_STATEMENT_BASE64_LENGTH
      max_body_length -= 20
    end

    raise "Failed to generate problem statement within size limits"
  end

  # Generate PR body for issue assignment
  # See https://github.com/github/sweagentd/blob/main/internal/events/on_issue_assigned.go#L384
  #
  # Params:
  # - issue: an Issue object
  #
  # Returns: formatted PR body string
  sig { params(issue: Issue, agent_instructions: T.nilable(String)).returns(T::Array[String]) }
  def self.generate_pr_body(issue:, agent_instructions: nil)
    issue_body = issue.body || ""

    # Quote the original issue description
    quoted_body = issue_body.gsub("\n", "\n> ")

    body_placeholder = "Thanks for assigning this issue to me. I'm starting to work on it and will keep this PR's description up to date as I form a plan and make progress."

    # Only add original issue description if it is non-empty after trimming whitespace
    unless quoted_body.strip.empty?
      body_placeholder += "\n\n**Original issue description**:\n\n> #{quoted_body}"
    end

    body_suffix = ""
    if agent_instructions && !agent_instructions.strip.empty?
      visible_instructions = agent_instructions.strip
      normalized = visible_instructions.gsub(/\r\n?/, "\n")
      quoted_instructions = normalized.gsub(/\A/, "> ").gsub(/\n/, "\n> ")
      body_suffix += "#{SECTION_SEPARATOR}**Additional instructions:**\n\n#{quoted_instructions}\n\n"
    end
    # Use `owner/repo#issue_number` instead of just number because the PR might be in a different repo
    body_suffix += "Fixes #{issue.name_with_display_owner_reference}"

    append_body_suffix_to_placeholder = FeatureFlag.vexi.enabled?(:issues_copilot_append_body_suffix, issue.repository, issue.repository&.owner, default: false)
    body_placeholder += "\n\n#{body_suffix}" if append_body_suffix_to_placeholder

    [body_placeholder, body_suffix]
  end

  # Filter comments to exclude:
  # 1. Minimized comments
  # 2. Comments from users without write access to the repository
  # 3. Comments from bots (except github-copilot[bot])
  # This matches the filtering logic used in sweagentd
  sig { params(comments: T::Array[T.any(IssueComment, T.untyped)], repository: Repository).returns(T::Array[T.any(IssueComment, T.untyped)]) }
  def self.filter_comments_for_problem_statement(comments, repository)
    comments.filter do |comment|
      # Skip minimized comments
      next false if comment.minimized?

      # Skip comments from users without write access
      # For issue comments, we check issues write permission
      if comment.user.present?
        next false unless repository.resources.issues.writable_by?(comment.user)

        # Skip comments from bots, except for github-copilot[bot]
        if comment.user.type == "Bot" && comment.user.display_login != "github-copilot[bot]"
          next false
        end
      end

      true
    end
  end

  # Helpers

  # Replaces bare issue references `#1` in issue or comment body with
  # global repo issue reference `owner/repo#num`
  # Inspired by IssueTransfer#replace_bare_issue_mentions
  #
  # @param body [String, nil] - the body text to process
  # @param repository [Repository] - the repository context for the issue
  #
  # @return [String, nil]
  sig { params(body: T.nilable(String), repository: Repository).returns(T.nilable(String)) }
  def self.replace_bare_issue_mentions(body, repository)
    return body if body.nil?

    issue_reference_text = /(?<=\s|^)(gh-|#)(\d+)\b/i

    body.gsub(issue_reference_text) do
      _pound, number = $1, $2.to_i
      "#{repository.name_with_display_owner}##{number}"
    end
  end

  sig { params(issue: Issue, comments: T::Array[T.untyped], agent_instructions: T.nilable(String), max_body_length: Integer, max_comment_length: Integer).returns(String) }
  def self.build_statement(issue, comments, agent_instructions, max_body_length, max_comment_length)
    repository = T.must(issue.repository)

    xml = []
    xml << ""
    xml << SECTION_SEPARATOR
    xml << ISSUE_SECTION_HEADER
    xml << ""
    xml << xml_tag("issue_title", issue.title)
    processed_body = replace_bare_issue_mentions(issue.body, repository)
    xml << xml_tag("issue_description", truncate(processed_body, max_body_length))
    xml << ""
    if agent_instructions && !agent_instructions.empty?
      xml << xml_tag("agent_instructions", agent_instructions)
      xml << ""
    end
    xml << ISSUE_COMMENTS_HEADING
    xml << "<comments>"
    comments.each do |comment|
      xml << build_comment_xml(comment, max_comment_length, repository)
    end
    xml << "</comments>"
    xml << ""
    xml.join("\n")
  end

  sig { params(comment: T.untyped, max_length: Integer, repository: T.nilable(Repository)).returns(String) }
  def self.build_comment_xml(comment, max_length, repository = nil)
    author = if comment.user&.display_login == "github-copilot[bot]"
      "@copilot"
    elsif comment.user&.type == "Bot"
      "#{comment.user.display_login}[bot]"
    else
      "@#{comment.user&.display_login}"
    end

    comment_body = comment.body || ""
    if repository
      comment_body = replace_bare_issue_mentions(comment_body, repository)
    end
    body = truncate(comment_body, max_length)

    # Use comment_new for non-copilot comments, comment_old for copilot
    tag = (author == "@copilot") ? "comment_old" : "comment_new"
    "<#{tag}><author>#{author}</author><body>\n#{body}</body></#{tag}>"
  end

  sig { params(tag: String, content: T.nilable(String)).returns(String) }
  def self.xml_tag(tag, content)
    "<#{tag}>#{content}</#{tag}>"
  end

  sig { params(str: T.nilable(String), max_length: T.nilable(Integer)).returns(T.nilable(String)) }
  def self.truncate(str, max_length)
    return str if max_length.nil? || max_length <= 0 || str.nil? || str.length <= max_length
    (max_length > 3) ? "#{str[0...(max_length - 3)]}..." : str[0...max_length]
  end

  sig { params(str: String).returns(Integer) }
  def self.base64_length(str)
    [str].pack("m0").length
  end

  sig { params(issue: Issue, agent_instructions: T.nilable(String)).returns(Integer) }
  def self.approximate_max_truncated_issue_body_length(issue, agent_instructions)
    # Estimate header/comments size (without body)
    xml = []
    xml << ""
    xml << SECTION_SEPARATOR
    xml << ISSUE_SECTION_HEADER
    xml << ""
    xml << xml_tag("issue_title", issue.title)
    xml << xml_tag("issue_description", "")
    xml << ""
    if agent_instructions && !agent_instructions.empty?
      xml << xml_tag("agent_instructions", agent_instructions)
      xml << ""
    end
    xml << ISSUE_COMMENTS_HEADING
    xml << "<comments>"
    xml << "</comments>"
    xml << ""
    base = xml.join("\n").length
    [(MAX_PROBLEM_STATEMENT_BASE64_LENGTH * 0.75).to_i - base, 0].max
  end

  sig { params(error: Exception).returns(T::Boolean) }
  def self.timeout_error?(error)
    TIMEOUT_ERROR_CLASSES.any? { |cls| error.is_a?(cls) } || error.message.match?(TIMEOUT_ERROR_PATTERNS)
  end
end
