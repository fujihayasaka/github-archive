# typed: true
# frozen_string_literal: true

class MemexProject
  # This class matches the filter interface required to be used within the Filter class.  Another example
  # of a filter interface implementation is the ColumnFilter class.  This class should be used when the `is`
  # keyword is present within a filter string.  This class understands how to determine if a project item
  # matches an is keyword or a set of keywords.
  #
  # This logic was first implemented within our Memex TypeScript library and is simply being re-implemented
  # with Ruby:
  #   - src/client/components/filter-bar/helpers/search-filter.ts (matchMetaProps)
  #   - src/client/hooks/use-item-matches-filter-query.ts (itemMatchesFilterQuery)
  class IsKeywordFilter
    # Localize the types we care about.
    module ContentTypes
      DRAFT_ISSUE  = DraftIssue.name
      ISSUE        = Issue.name
      PULL_REQUEST = PullRequest.name
    end

    # List out all the potential keywords a user could enter.
    module Keywords
      # state
      CLOSED = "closed"
      MERGED = "merged"
      OPEN   = "open"

      # type
      ISSUE = "issue"
      PR    = "pr"

      # state or type
      DRAFT = "draft"
    end

    # Keep these private until we need to expose them.
    private_constant :ContentTypes, :Keywords

    def initialize(keywords: [], negated: false)
      @keywords = Array(keywords)
      @negated  = !!negated

      freeze
    end

    def to_s
      "#{negated ? "-" : ""}is:#{keywords.join(',')}"
    end

    def absence
      false
    end

    def column_id
      ItemMetadata.name
    end

    # This method will loop through all the keywords and determine if an item matches the keywords.
    # The logic here is a bit complicated and is probably best explained with a matrix (X denotes a match):
    #
    #   Item         | is:draft | is:issue | is:pr | is:open | is:closed | is:merged
    #   ------------ | -------- | -------- | ----- | ------- | --------- | ---------
    #   Open Issue   |          |     X    |       |    X    |           |
    #   Closed Issue |          |     X    |       |         |     X     |
    #   Draft Issue  |     X    |     X    |       |    X    |           |
    #   Draft PR     |     X    |          |   X   |    X    |           |
    #   Merged PR    |          |          |   X   |         |     X     |     X
    #   Open PR      |          |          |   X   |    X    |           |
    #   Closed PR    |          |          |   X   |         |     X     |
    #
    # Special Negation Rule:
    #   Applying negation to any of the above filters simply inverts the results. For example:
    #   "-is:merged" actually would return every item in the list minus the merged PR. This is important
    #   to call out because it could be a bit counter-intuitive: since issues do not have a merge status
    #   someone would expect is:merged and -is:merged results to never include issues, but in reality
    #   the negative case does.
    #
    # Parameters:
    #   - item_metadata: Instance of MemexProject::ItemMetadata representing an item.
    #
    # Returns:
    #   - true if the item metadata matches the above matrix and rules, false it if does not.
    def matches?(item_metadata)
      keep_searching = T.let(false, T::Boolean)

      keywords.each do |keyword|
        # keep_searching will resolve to true if it matches either on state or type, depending on the items type.
        keep_searching =
          case keyword.to_s.downcase
          when Keywords::OPEN, Keywords::CLOSED, Keywords::MERGED
            matches_state?(item_metadata, keyword)
          when Keywords::ISSUE, Keywords::PR
            matches_type?(item_metadata, keyword)
          when Keywords::DRAFT
            matches_type?(item_metadata, keyword) || matches_state?(item_metadata, keyword)
          else
            false
          end


        # Negated state and the last keyword did not match => will short-circuit and return false.
        # An example of this would be:
        #  "-is:open,pr" => break on first keyword if the item is not open no matter what the type is.

        # Non-negated state and the last keyword matched => will short-circuit and return true.
        # An example of this would be:
        #  "is:open,pr" => break on the first keyword if the item is open no matter what the type is.

        # All other combinations will goto the next keyword and try again.
        # An example of this would be:
        #  "is:open,pr" => try the next keyword if the item is closed, maybe the next keyword will match.
        #  "-is:open,pr" => try the next keyword if the item is closed, maybe the next keyword will match.
        break if (negated && !keep_searching) || (!negated && keep_searching)
      end

      keep_searching
    end

    private

    attr_reader :keywords, :negated

    def matches_type?(item_metadata, value)
      case item_metadata.content_type
      when ContentTypes::DRAFT_ISSUE
        matches = (value == Keywords::DRAFT) || (value == Keywords::ISSUE)

        negated ? !matches : matches
      when ContentTypes::ISSUE
        matches = value == Keywords::ISSUE

        negated ? !matches : matches
      when ContentTypes::PULL_REQUEST
        matches =
          if value == Keywords::DRAFT
            item_metadata.state == Keywords::OPEN &&
            item_metadata.is_draft
          else
            value == Keywords::PR
          end

        negated ? !matches : matches
      else
        false
      end
    end

    def matches_state?(item_metadata, value)
      case item_metadata.content_type
      when ContentTypes::ISSUE
        matches = item_metadata.state == value

        negated ? !matches : matches
      when ContentTypes::PULL_REQUEST
        matches =
          item_metadata.state == value || # for open, closed, and merged states
          (item_metadata.state == Keywords::MERGED && value == Keywords::CLOSED) || # merged items are considered closed
          (item_metadata.is_draft && item_metadata.state == Keywords::OPEN && value == Keywords::DRAFT) # draft PRs cound for drafts

        negated ? !matches : matches
      when ContentTypes::DRAFT_ISSUE
        # is:open should return draft issues
        return !negated if value == Keywords::OPEN
        return negated  if value == Keywords::CLOSED || value == Keywords::MERGED

        false
      else
        false
      end
    end
  end
end
