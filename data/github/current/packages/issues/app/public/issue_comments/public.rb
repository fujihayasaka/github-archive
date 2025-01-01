# typed: strict
# frozen_string_literal: true

module IssueComments
  module Public
    extend self
    extend T::Sig

    include Kernel

    sig { params(id: Integer, repository_id: Integer).returns(T.nilable(IssueComment)).checked(:always).on_failure(:raise) }
    def by_id(id, repository_id:)
      ::IssueComment.find_by(id:, repository_id:)
    end

    # Retrieve comment counts for all issues active during the time
    # period. Optimized to retrieve all counts in a single query.
    #
    # Returns a hash of issue_id => count mappings.
    sig { params(repository_id: Integer, since: Time, viewer: User).returns(T::Hash[Integer, Integer]) }
    def count_by_issue_since(repository_id, since, viewer)
      relevant_issue_comments = IssueComment.
        where(repository_id:).
        where("created_at > ?", since).
        filter_spam_for(viewer)

      relevant_issue_comments.group(:issue_id).count
    end
  end
end
