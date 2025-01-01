# typed: true
# frozen_string_literal: true

class IndexSourceCodeJob < ApplicationJob
  queue_as :index_high
  include Repositories::Domain::Provider

  # Update the search index with the information from `before` and `after`
  # commit SHAs from a push event. Files will be added, updated, or
  # removed from the search index.
  #
  def perform(repo_id, before, after, ref, *args)
    return unless GitHub.use_elastomer_code_search?
    return unless GitHub.code_search_indexing_enabled?

    repository = Repositories.domain.by_id(repo_id)
    return unless repository

    searchable = T.cast(repository, Repository).code_is_searchable? # rubocop:todo GitHub/AvoidCast

    Elastomer.each_writable_index(Elastomer::Indexes::CodeSearch) do |config|
      cs = Elastomer::Indexes::CodeSearch.new(config.name, config.cluster)
      head_ref, head = cs.indexed_head(repository.id)

      # remove all code from the search index if the master branch has
      # changed or if the repository should not be shown in the search
      # results
      if head != T.cast(repository, Repository).default_branch || (head_ref && !searchable) # rubocop:todo GitHub/AvoidCast
        cs.remove_code(repository.id) if head_ref
      end
    end
    return unless searchable

    # NOTE: This should hit the (repository_id, after) index
    push = repositories_domain.pushes.by_repo_id_and_after(repository_id: repo_id, before: before, after: after, ref: ref)

    pushed_at = !push.nil? ? push.pushed_at.utc.to_f : nil

    # if the after SHA is null, that means we are deleting this branch
    if GitHub::NULL_OID == after
      RemoveFromSearchIndexJob.perform_later("code", repository.id, { pushed_at: pushed_at })
    else
      Search.add_to_search_index("code", repository.id, { head_commit_sha: after, pushed_at: pushed_at })
    end

    nil
  rescue StandardError => err # rubocop:todo Lint/GenericRescue
    Failbot.report(err.with_redacting!)
  end
end
