# typed: true
# frozen_string_literal: true

# Defines a filter that identifies Issue references inside a string
# Params:
#  - text: the text to be filtered
#  - viewer: the user making the request against whom the permissions for the issue refs are checked
#  - multi_refs: whether the filter should identify multiple references and ignore meaningless text
#                when set to false, any un-matchable text will cause the filter to ignore actual matches
#                example: "https://github.com/github/github/issue/2 test" will return 0 references
# Returns:
# - first_reference: the first identifiable reference in the string
# - references: an array of all identifiable references in the string
class DraftIssueReferenceFilter
  include GitHub::IssueReferenceResolution
  def initialize(text:, viewer:, multi_refs: false)
    @text = text.strip.chomp("/").chomp("#")
    @viewer = viewer
    @multi_refs = multi_refs
    scan_for_references
  end

  def first_reference
    if @non_reference_text.strip.empty? && @references.any?
      @references.first
    else
      nil
    end
  end

  def references
    if (@non_reference_text.strip.empty? || @multi_refs) && @references.length > 0
      @references
    else
      []
    end
  end

  def non_reference_text
    @non_reference_text.strip.gsub(/\s+/, " ")
  end

  def self.reference_patterns
    Regexp.union(
      GitHub::HTML::IssueMentionFilter::REPO_ISSUE_REFERENCE,
      GitHub::HTML::IssueMentionFilter.full_url_issue_mention,
    )
  end

  private

  def is_non_ref_text_empty?
    @non_reference_text.gsub(/[\s,[\r\n]]+/, "").empty?
  end

  def scan_for_references
    references = []

    @non_reference_text = @text.gsub(self.class.reference_patterns) do
      # In this loop, we repeatedly identify and replace issue references with
      # the value yielded in each iteration; when we're done, `gsub` returns
      # the final result of all of our subsitutions.

      match = T.must(Regexp.last_match)

      # REPO_ISSUE_REFERENCE match e.g. "github/memex#123".
      repo_prefix, repo_nwo, repo_issue_number = match[1], match[2], match[3]
      if repo_issue_number && repo_nwo&.include?("/")
        # Full name with owner in reference
        references << [repo_nwo, repo_issue_number]

        # Remove nwo and issue number but retain prefix text
        next repo_prefix
      end

      # FULL_URL_ISSUE_MENTION match e.g. "https://github.com/github/memex/issues/123".
      url_nwo, url_issue_number = match[4], match[5]
      if url_issue_number
        references << [url_nwo, url_issue_number]

        # Remove URL
        next ""
      end

      # We should never get here because the above cases should be exhaustive.
      # As a fallback though, return the unmodified match string.
      match[0]
    end

    @references = references.reduce([]) do |valid_references, (repository, number)|
      repository = find_repo(repository, nil)
      next valid_references unless repository&.readable_by?(@viewer)

      issue = repository.issues.includes(:pull_request).find_by_number(number)
      next valid_references unless issue

      valid_references << (issue.pull_request || issue)
    end

    nil
  end
end
