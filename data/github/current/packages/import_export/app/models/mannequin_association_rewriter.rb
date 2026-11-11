# typed: true
# frozen_string_literal: true

class MannequinAssociationRewriter
  # Associations that require search index updates after transfer
  SEARCHABLE_ASSOCIATIONS = {
    issues: "issue",
    pull_requests: "pull_request"
  }.freeze

  TRANSFERABLE_ASSOCIATIONS = [
    :commit_comments,
    :created_projects,
    :issue_comments,
    :issues,
    :project_cards,
    :projects,
    :pull_request_review_comments,
    :pull_request_reviews,
    :pull_requests,
    :release_mentions,
    :releases,
    :review_requests,
    :subjected_issue_event_details,
  ].freeze

  attr_reader :source, :target

  def initialize(source, target)
    @source = source
    @target = target
  end

  def rewrite!
    TRANSFERABLE_ASSOCIATIONS.each do |association|
      transfer_association(association)
    end

    Assignments::Public.transfer_to_assignee(source, target) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    Attachments::Public.transfer_to_attacher(source.id, target.id)
    CrossReferences::Public.transfer_to_actor(source.id, target.id)
    IssueEvents::Public.transfer_to_actor(source.id, target.id)
  end

  private

  def transfer_association(association)
    search_type = SEARCHABLE_ASSOCIATIONS[association]

    if search_type && reindex_enabled?
      # For searchable associations, enqueue reindex jobs immediately after each batch.
      # This ensures idempotency: if the job crashes and retries, already-transferred
      # records won't be in source.issues/pull_requests anymore, and their reindex
      # jobs were already enqueued.
      source.send(association).transfer_to(target) do |transferred_ids|
        enqueue_search_index_jobs_for_batch(search_type, transferred_ids)
      end
    else
      source.send(association).transfer_to(target)
    end
  end

  def enqueue_search_index_jobs_for_batch(search_type, ids)
    ids.each do |id|
      Search.add_to_search_index(search_type, id, queue: :index_high_importing)
    end
  end

  def reindex_enabled?
    FeatureFlag.vexi.enabled?(:octoshift_mannequin_reclaiming_reindex_issues_and_prs, default: false)
  end
end
