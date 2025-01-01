# typed: true
# frozen_string_literal: true

class BatchReindexIssueDependenciesJob < BatchedJob
  queue_as :batch_reindex_issue_dependencies
  retry_on_dirty_exit

  sig do
    params(
      repository_id: Integer,
      timestamp: Time,
      offset_item_id: Integer,
      progress: Integer,
      options: T.untyped,
    ).returns(T::Array[Integer])
  end
  def next_batch(repository_id:, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    Issue
      .where("repository_id = ?", repository_id)
      .where("id > ?", offset_item_id)
      .order(id: :asc)
      .limit(BATCH_SIZE)
      .pluck(:id)
  end

  sig { params(issue_ids: T::Array[::Integer], args: T.untyped, kwargs: T.untyped).returns(T.nilable(Integer)) }
  def next_batch_offset_item_id(issue_ids, *args, **kwargs)
    # Issues are ordered by ID at query time, so last one will be max
    issue_ids.last
  end

  sig { params(batch: T::Array[Issue], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    return if batch.empty?

    # Provide a list of repository ids to ignore to only reindex issue dependencies outside of these repos.
    repo_ids_to_ignore = options[:repo_ids_to_ignore] || []

    # Get unique ids of all related issue dependencies.
    # This can be a maximum of 200 * BATCH_SIZE (default 100).
    related_issue_dependency_ids = IssueDependency
      .where(source_issue_id: batch)
      .or(IssueDependency.where(target_issue_id: batch))
      .pluck(:source_issue_id, :target_issue_id)
      .flatten
      .uniq
    return if related_issue_dependency_ids.empty?

    # Get issues not in the repo(s) to ignore, in batches, and re-index each issue.
    related_issue_dependency_ids.in_groups_of(BATCH_SIZE) do |issue_dependency_ids|
      issues_to_sync = Issue
        .where(id: issue_dependency_ids)
        .and(Issue.where.not(repository_id: repo_ids_to_ignore))
      next if issues_to_sync.empty? # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      issues_to_sync.each(&:synchronize_search_index) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end
end
