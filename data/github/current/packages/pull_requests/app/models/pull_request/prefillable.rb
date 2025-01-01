# typed: true
# frozen_string_literal: true

module PullRequest::Prefillable
  extend ActiveSupport::Concern

  class_methods do

    # Public: Preloads PullRequest repository and user associations.
    sig do
      params(
        pulls: T.any(ActiveRecord::Relation, T::Array[PullRequest]),
        mirror: T::Boolean,
        issues: T.nilable(T.any(ActiveRecord::Relation, T::Array[Issue])),
        repository: T.nilable(Repository),
        users: T.nilable(T.any(ActiveRecord::Relation, T::Array[User]))
      )
      .void
    end
    def prefill_associations(pulls, mirror: false, issues: nil, repository: nil, users: nil)
      associations_to_prefill = [
        :auto_merge_request, :user, :base_user, :head_user,
        { review_requests: :reviewer },
        { repository: [:owner, :organization] },
        { base_repository: [:owner, :organization] },
        { head_repository: [:owner, :organization] },
        { issue: [:assignees, :repository, :user] }
      ]
      available_records = issues.to_a + users.to_a + [repository].compact
      GitHub::PrefillAssociations.prefill_associations(pulls, associations_to_prefill,
        available_records: available_records)

      # Repositories
      repos = pulls.flat_map { |p| [p.repository, p.base_repository, p.head_repository] }.compact
      Repository.prefill_associations(repos, mirror: mirror, owner: false)
    end

    # Public: Preloads PullRequest associations for the REST API List Repo pulls endpoint (/repo/:repo_id/pulls).
    #         It is a duplicate of the prefill_associations method but with specific associations to preload
    #         for the /repo/:repo_id/pulls endpoint that optimize for performance for this endpoint.
    sig do
      params(
        pulls: T.any(ActiveRecord::Relation, T::Array[PullRequest]),
        current_user: T.nilable(User),
        mirror: T::Boolean,
        issues: T.nilable(T.any(ActiveRecord::Relation, T::Array[Issue])),
        repository: T.nilable(Repository),
        users: T.nilable(T.any(ActiveRecord::Relation, T::Array[User]))
      )
      .void
    end
    def prefill_rest_api_list_repo_pulls(pulls, current_user, mirror: false, issues: nil, repository: nil, users: nil)
      associations_to_prefill = [
        :auto_merge_request, :user, :base_user, :head_user,
        { repository: [:owner, :organization] },
        { base_repository: [:owner, :organization] },
        { head_repository: [:owner, :organization] },
        { issue: [:assignees, :repository, :user] }
      ]
      available_records = issues.to_a + users.to_a + [repository].compact
      GitHub::PrefillAssociations.prefill_associations(pulls, associations_to_prefill,
        available_records: available_records)

      # Repositories
      repos = pulls.flat_map { |p| [p.repository, p.base_repository, p.head_repository] }.compact
      Repository.prefill_associations(repos, mirror: mirror, owner: false)

      prefill_author_associations(pulls, current_user)

      # Issues have already been preloaded by  so there is no chance of N+1 on the map
      # issue call below as it is already in memory.
      GitHub::PrefillAssociations.prefill_associations(pulls.map(&:issue), :labels)

      GitHub::PrefillAssociations.prefill_associations(
        pulls,
        { review_requests_pending: :reviewer }
      )

      Configurable.preload_configuration(repos) if GitHub.flipper[:pull_requests_api_preload_configs].enabled?
    end

    # Public: Preloads author_association field for the list of pull requests for the given current_user.
    sig { params(pulls: T.any(ActiveRecord::Relation, T::Array[PullRequest]), current_user: T.nilable(User)).void }
    def prefill_author_associations(pulls, current_user)
      promises = pulls.map do |associable|
        CommentAuthorAssociation.new(comment: associable, viewer: current_user).async_to_sym.then do |sym|
          associable.preload_attr(:author_association_symbol, sym)
        end
      end

      Promise.all(promises).sync
    end

  end
end
