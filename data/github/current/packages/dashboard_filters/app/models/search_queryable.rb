# typed: true
# frozen_string_literal: true

module SearchQueryable
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ActiveRecord::Base }

  include GitHub::UTF8
  # Terms that are considered User-like login references.
  LOGIN_REF_QUERY_TERMS = %i(
    answered-by
    assignee
    author
    commenter
    involved
    mentions
    org
    reviewed-by
    user
  )

  # Terms that are parsed by other searches.
  ISSUE_TERMS = ::Search::Queries::IssueQuery::field_list
  DISCUSSION_TERMS = ::Search::Queries::DiscussionQuery::field_list

  # Terms that do not rely on a scoping repository.
  UNSCOPED_QUERY_TERMS = %i(assignee author user repo project)

  # Terms that rely on a scoping repository to query DB records for.
  REPO_SCOPED_QUERY_TERMS = %i(category label milestone)

  # Final Set of all terms that will be parsed from a query string.
  KNOWN_QUERY_TERMS = Set.new([
    *ISSUE_TERMS,
    *DISCUSSION_TERMS,
    *LOGIN_REF_QUERY_TERMS,
    *UNSCOPED_QUERY_TERMS,
    *REPO_SCOPED_QUERY_TERMS
  ]).freeze

  SEARCH_TYPES = {
    issues: 0,
    pull_requests: 1,
    discussions: 2,
  }.freeze

  def compressed_query
    utf8(read_attribute(:compressed_query))
  end
  alias_method :query, :compressed_query

  def query_terms
    return [] if query.blank?

    Search::ParsedQuery.parse(query, terms: KNOWN_QUERY_TERMS.to_a).map do |(key, value, negative)|
      did_match_term = key.is_a?(Symbol) && KNOWN_QUERY_TERMS.include?(key)
      repo_scoped_term = REPO_SCOPED_QUERY_TERMS.include?(key)

      if did_match_term
        {
          term: (negative ? "-" : "") + "#{key}:#{Search::ParsedQuery.encode_value(value)}",
          matched: true,
          name: key,
          value: value,
          negative: !!negative,
          scoping_repository_id: (T.unsafe(self).scoping_repository_id if repo_scoped_term),
        }.compact
      else
        {
          term: key,
          matched: false,
        }
      end
    end
  end

  included do
    T.bind(self, T.class_of(ActiveRecord::Base))
    # enums
    enum :search_type, SEARCH_TYPES, suffix: true

    # validations
    validates :query, bytesize: { maximum: MYSQL_UNICODE_BLOB_LIMIT }, unicode: true

    validates :search_type, presence: true

    # attributes
    attribute :compressed_query, CompressedBinary.new(self.name, "query")
    alias_attribute :query, :compressed_query
  end
end
