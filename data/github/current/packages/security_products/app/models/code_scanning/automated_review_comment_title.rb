# typed: strict
# frozen_string_literal: true

module CodeScanning
  module AutomatedReviewCommentTitle
    TITLE_BYTESIZE_LIMIT = T.let(1024, Integer)
    TITLE_TOOL_NAME_BYTESIZE_LIMIT = T.let(255, Integer)
    TITLE_TRUNCATION_OMISSION = T.let("...", String)

    sig do
      params(
        tool_name: String,
        rule_short_description: String,
      ).returns(String)
    end
    def self.build(tool_name:, rule_short_description:)
      title = "#{tool_name} / #{rule_short_description}"

      GitHub.dogstats.distribution("code_scanning.pr_review_comment.title.tool_name_bytes", tool_name.bytesize)
      GitHub.dogstats.distribution("code_scanning.pr_review_comment.title.rule_description_bytes", rule_short_description.bytesize)
      GitHub.dogstats.distribution("code_scanning.pr_review_comment.title.combined_bytes", title.bytesize)

      return title if title.bytesize <= TITLE_BYTESIZE_LIMIT

      truncated_tool_name = tool_name.truncate_bytes(TITLE_TOOL_NAME_BYTESIZE_LIMIT, omission: TITLE_TRUNCATION_OMISSION)
      title_prefix = "#{truncated_tool_name} / "

      available_rule_description_bytes = TITLE_BYTESIZE_LIMIT - title_prefix.bytesize
      truncated_rule_short_description = rule_short_description.truncate_bytes(available_rule_description_bytes, omission: TITLE_TRUNCATION_OMISSION)
      truncated_title = "#{title_prefix}#{truncated_rule_short_description}"

      GitHub.dogstats.increment(
        "code_scanning.pr_review_comment.title.truncated",
        tags: [
          "tool_name_truncated:#{truncated_tool_name != tool_name}",
          "rule_description_truncated:#{truncated_rule_short_description != rule_short_description}",
        ]
      )
      GitHub.dogstats.distribution("code_scanning.pr_review_comment.title.truncated_bytes", truncated_title.bytesize)

      truncated_title
    end
  end
end
