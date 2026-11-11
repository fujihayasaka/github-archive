# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class DuplicateKeywordFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "p", reject: "blockquote p")
    ANCHOR_TAG = :a

    ISSUE_DUPLICATE_LOCATIONS = %w[IssueComment PullRequestComment].freeze
    PULL_REQUEST_TARGET = "pull request".freeze
    ISSUE_TARGET = "issue".freeze

    DUPLICATE_KEYWORD = "Duplicate of".freeze
    DUPLICATE_LEADER = /\A#{DUPLICATE_KEYWORD}\W/
    REPO_DUPLICATE_ISSUE_NUMBER_REFERENCE = /#{DUPLICATE_LEADER}#{GitHub::HTML::IssueMentionFilter::MARKER}#{GitHub::HTML::IssueMentionFilter::NUMBER}\z/i
    REPO_DUPLICATE_ISSUE_NWO_AND_NUMBER_REFERENCE = /#{DUPLICATE_LEADER}#{GitHub::HTML::IssueMentionFilter::NAME_OR_NWO}#{GitHub::HTML::IssueMentionFilter::MARKER}#{GitHub::HTML::IssueMentionFilter::NUMBER}\z/i

    def self.cache_key(context)
      [
        context[:location],
        # from @html_filter.issue_reference
        GitHub::HTML::IssueMentionFilter.cache_key(context),
      ].reject(&:blank?).join(":")
    end

    def initialize(*args)
      super
      @html_filter = GitHub::HTML::IssueMentionFilter.new("", context, result)
    end

    def selector
      SELECTOR
    end

    def call(node)
      return node unless duplicate_keyword_highlighting_supported?(node)

      node_text = node.text_content
      canonical_issue_match = canonical_issue_reference_matches(node_text)
      canonical_issue_number = canonical_issue_match[1] || canonical_issue_match[3] || canonical_issue_match[5]
      canonical_issue_nwo = canonical_issue_match[2] || canonical_issue_match[4]
      canonical_issue_reference = @html_filter.issue_reference(
        DUPLICATE_KEYWORD,
        canonical_issue_number,
        canonical_issue_nwo,
      )

      if canonical_issue_reference.present?
        subnode = issue_mention_text_or_anchor_node(node)
        issue_mention_tag = GitHub::Goomba::IssueMentionFilter.
          new(context, result).
          call(subnode)
        if issue_mention_tag.nil?
          if is_element_node?(subnode) && subnode["gh:issue-mention"]
            issue_mention_tag = subnode.to_html
            subnode.remove_attribute("gh:issue-mention")
          else
            return
          end
        end

        formatted_text = text_with_highlighted_duplicate_keyword(
          issue_mention_tag: issue_mention_tag.sub(DUPLICATE_LEADER, ""),
          issue_number: canonical_issue_number,
        )
        ActionController::Base.helpers.content_tag(:p, formatted_text)
      end
    end

    private

    def duplicate_keyword_highlighting_supported?(node)
      is_text_node?(node.children.first) &&
        node_has_no_siblings?(node) &&
        ISSUE_DUPLICATE_LOCATIONS.include?(location) &&
        matches_duplicate_keyword_syntax?(node.text_content)
    end

    def node_has_no_siblings?(node)
      node.previous_sibling.nil? && node.next_sibling.nil?
    end

    def matches_duplicate_keyword_syntax?(node_text)
      node_text.present? && canonical_issue_reference_matches(node_text).present?
    end

    def repo_duplicate_issue_url_reference
      /#{DUPLICATE_LEADER}#{GitHub::HTML::IssueMentionFilter.full_url_issue_mention}\z/i
    end

    def duplicate_issue_reference_pattern
      Regexp.union(
        REPO_DUPLICATE_ISSUE_NUMBER_REFERENCE,
        REPO_DUPLICATE_ISSUE_NWO_AND_NUMBER_REFERENCE,
        repo_duplicate_issue_url_reference,
      )
    end

    def canonical_issue_reference_matches(text)
      @duplicate_keyword_matches ||= text.match(duplicate_issue_reference_pattern) || []
    end

    def duplicate_keyword_text(node_text)
      if canonical_issue_reference_matches(node_text).present?
        DUPLICATE_KEYWORD
      end
    end

    def location_description
      if %w[PullRequest PullRequestComment].include?(location)
        PULL_REQUEST_TARGET
      elsif location == "IssueComment"
        ISSUE_TARGET
      end
    end

    def highlight_keyword(issue_number)
      tooltip_label = "This #{location_description} is a duplicate of ##{issue_number}"
      attrs = { "aria-label" => tooltip_label, "class" => "issue-keyword tooltipped tooltipped-se" }
      ActionController::Base.helpers.content_tag(:span, DUPLICATE_KEYWORD, attrs)
    end

    def text_with_highlighted_duplicate_keyword(issue_mention_tag:, issue_number:)
      if issue_mention_tag.present?
        stripped_html_safe_issue_mention_tag = safe_html_if_sanitized(issue_mention_tag.strip)
        highlighted_duplicate_keyword = highlight_keyword(issue_number)
        EscapeHelper.safe_join([highlighted_duplicate_keyword, stripped_html_safe_issue_mention_tag], " ")
      end
    end

    def location
      context[:location]
    end

    def issue_mention_text_or_anchor_node(node)
      if issue_mention_is_within_anchor?(node)
        node.children.last
      else
        node.children.first
      end
    end

    def issue_mention_is_within_anchor?(node)
      last_child_node = node.children.last

      node.children.size == 2 &&
        is_element_node?(last_child_node) && last_child_node.tag == ANCHOR_TAG
    end
  end
end
