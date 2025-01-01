# typed: strict
# frozen_string_literal: true

module Issues
  class Domain < GH::Domain::Base
    extend T::Sig

    sig { returns(Issues::Domain::IssueTypes) }
    memoize def issue_types # rubocop:disable GitHub/DocumentationDomainMethod
      Issues::Domain::IssueTypes.new(caller_service, actor: actor)
    end

    sig { returns(Issues::Domain::Labels) }
    memoize def labels # rubocop:disable GitHub/DocumentationDomainMethod
      Issues::Domain::Labels.new(caller_service, actor: actor)
    end

    skip_decoration :issue_types, :labels

    # Find an issue by its number for a given repository. Returns nil no issue is found.
    sig { params(number: Integer, repo_id: Integer).returns(T.nilable(IIssue)) }
    def by_number(number, repo_id:)
      ::Issue.find_by(repository_id: repo_id, number: number)
    end

    # Returns a hash of open issue and pull request counts for a list of repository ids.
    sig { params(repository_ids: T::Array[Integer], return_nil_on_failure: T::Boolean).returns(T.nilable(T::Hash[[Integer, T::Boolean], Integer])) }
    def open_issue_and_pr_counts(repository_ids:, return_nil_on_failure: false)
      begin
        ::Issue.where(state: :open, repository_id: repository_ids, user_hidden: false)
          .group(:repository_id, :has_pull_request)
          .count
      rescue ActiveRecord::ActiveRecordError => error
        return nil if return_nil_on_failure
        raise error
      end
    end
  end
end
