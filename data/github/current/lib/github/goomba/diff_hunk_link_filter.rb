# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class DiffHunkLinkFilter < InputFilter
    include ActionView::Helpers::TagHelper

    DIFF_HUNK_LINK_PATTERN = /\[(?<link_text>[^,"]+?)\]\(diffhunk:\/\/(?<hash_param>[^,"`\)]+)\)/

    def self.cache_key(context)
      "diff-hunk-link-filter-v1"
    end

    def self.enabled?(context)
      # only run this filter on a PR description or a PR comment
      (context[:subject].is_a?(Issue) && context[:subject].pull_request?) ||
        (context[:subject].is_a?(IssueComment) && context[:subject].issue.pull_request?) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    def call(input)
      return "" if input.nil?

      if input.match?(DIFF_HUNK_LINK_PATTERN)
        input
          .to_enum(:scan, DIFF_HUNK_LINK_PATTERN)
          .map { Regexp.last_match }
          .each { |match| input = replace_diff_hunk_link_with_pr_files_tab_link(input:, match:) }
      end

      input
    end

    private

    sig { params(input: String, match: T.nilable(MatchData)).returns(String) }
    def replace_diff_hunk_link_with_pr_files_tab_link(input:, match:)
      return input unless match && match[0] && match[:link_text] && match[:hash_param]

      input.sub(
        T.must(match[0]),
        "[#{match[:link_text]}](#{permalink}/files#{match[:hash_param]})"
      )
    end

    sig { returns(String) }
    def permalink
      if context[:subject].is_a?(IssueComment)
        return context[:subject].issue.permalink # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      end
      context[:subject].permalink
    end
  end
end
