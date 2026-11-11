# typed: strict
# frozen_string_literal: true

module Api::Serializer::MergeGroupDependency
  extend T::Helpers

  # Needed to find `simple_commit_hash`
  requires_ancestor { Api::Serializer::CommitsDependency }

  # Creates a Hash to be serialized to JSON.
  #
  # merge_group_entry - Merge Group Entry instance.
  # options - Hash (unused).
  #
  # This method takes a merge_group_entry and publishes a merge group, as the information to serialize isn't on the merge group, it's on the head of the merge group,
  # which is the last merge_group_entry in the group. This is an implementation detail that we shouldn't be exposing to customers, meaning this shouldn't be MergeGroupEntryEvent.
  # In addition, because the publish runs in a background job which fetches from the database, there could be a new head of a group between when the job is enqueued and when it is run,
  # making merge_group.last a potential race condition. By looking up the merge_group_entry we can be confident that a webhook will be triggered each time an entry is added to the queue.
  sig do
    params(
      entry: T.nilable(T.any(
        MergeQueueEntry,
        Hook::Event::MergeGroupEvent::MergeGroupProps,
      )),
      _options: T.untyped
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def merge_group_hash(entry, _options = {})
    return unless entry
    return unless pull_request = entry.pull_request
    return unless repository = entry.repository

    head_ref = entry.qualified_head_ref
    head_sha = entry.head_sha
    base_sha = entry.base_sha

    if FeatureFlag.vexi.enabled?(:merge_group_event_stack_base, repository, default: false)
      unqualified_base_ref = pull_request.stack_or_pull_base_ref_name
    else
      unqualified_base_ref = pull_request.base_ref
    end

    base_ref = repository.refs.find(unqualified_base_ref).qualified_name

    if head_sha.nil? || base_sha.nil? || head_ref.nil?
      GitHub.logger.info({
        "gh.repo.id": repository.id,
        "gh.pull_request.id": pull_request.id,
        "gh.pull_request.number": pull_request.number,
        "gh.merge_queue.webhook.error": "missing_data",
        "gh.merge_queue.webhook.base_sha": base_sha,
        "gh.merge_queue.webhook.head_sha": head_sha,
        "gh.merge_queue.webhook.head_ref": head_ref,
        "gh.merge_queue.webhook.base_ref": base_ref,
      })

      GitHub.dogstats.increment("merge_queue.webhook.failed")

      return
    end

    head_commit = unless GitRPC::Util.null_oid?(head_sha)
      Repositories.domain.commits.by_oid(repository:, commit_oid: head_sha)
    end

    {
      head_sha:,
      head_ref:,
      base_sha:,
      base_ref:,
      head_commit: simple_commit_hash(head_commit),
    }
  end
end
