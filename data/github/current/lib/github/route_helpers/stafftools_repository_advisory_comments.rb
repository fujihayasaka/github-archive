# typed: true
# frozen_string_literal: true

module GitHub
  module RouteHelpers
    extend T::Helpers
    requires_ancestor { Object }

    def gh_stafftools_repository_advisory_comments_path(advisory)
      expand_from_advisory \
        :stafftools_repository_repository_advisory_comments_path,
        advisory
    end

    def gh_first_stafftools_repository_advisory_comments_path(advisory)
      expand_from_advisory \
        :first_stafftools_repository_repository_advisory_comments_path,
        advisory
    end

    def gh_stafftools_repository_advisory_comment_path(comment)
      expand_from_advisory_comment \
        :stafftools_repository_repository_advisory_comment_path,
        comment
    end

    def gh_database_stafftools_repository_advisory_comment_path(comment)
      expand_from_advisory_comment \
        :database_stafftools_repository_repository_advisory_comment_path,
        comment
    end

    private

    def expand_from_advisory_comment(helper, comment)
      advisory = comment.repository_advisory
      repo = advisory.repository
      send(helper, repo.owner, repo.name, advisory.id, comment)
    end
  end
end
