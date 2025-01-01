# typed: strict
# frozen_string_literal: true

module DeletedIssues
  module Public
    extend self

    include Kernel

    sig { params(number: Integer, repository_id: Integer).returns(T.nilable(DeletedIssue)) }
    def by_number(number, repository_id:)
      ::DeletedIssue.find_by(number:, repository_id:)
    end

    sig { params(old_issue_id: Integer, repository_id: Integer).returns(T.nilable(DeletedIssue)) }
    def by_old_issue(old_issue_id, repository_id:)
      ::DeletedIssue.find_by(old_issue_id:, repository_id:)
    end

    sig { params(repository_id: Integer).returns(T::Array[DeletedIssue]) }
    def by_repo_desc(repository_id)
      ::DeletedIssue.where(repository_id:).order("id DESC").to_a
    end

    sig { params(repository_id: Integer, pagination: GH::Pagination::Base, sorts: T::Array[GH::Pagination::Sort]).returns(GH::Domain::Collection[DeletedIssue]) }
    def by_repo_desc_paginated(repository_id, pagination:, sorts:)
      scope = ::DeletedIssue.where(repository_id:)

      T.let(
        GH::Pagination::Paginator.paginate(
          scope: scope,
          pagination: pagination,
          sorts: sorts
        ),
        GH::Domain::Collection[DeletedIssue]
      )
    end
  end
end
