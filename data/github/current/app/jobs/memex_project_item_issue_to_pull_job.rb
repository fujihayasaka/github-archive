# typed: strict
# frozen_string_literal: true

# This job handles updating memex items' content when an issue is "converted" to a pull request via the REST api
class MemexProjectItemIssueToPullJob < BatchedJob
  extend T::Sig

  BATCH_SIZE = 100

  queue_as :memex_project_item_issue_to_pull
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(offset_item_id: Integer, options: T.untyped).returns(T::Array[MemexProjectItem]) }
  def next_batch(offset_item_id: 0, **options)
    issue_id = T.let(options.fetch(:issue_id), Integer)
    repository_id = T.let(options.fetch(:repository_id), Integer)
    pull_request_id = T.let(options.fetch(:pull_request_id), Integer)

    issue = Issue.find_by(id: issue_id, repository_id: repository_id)
    return [] unless issue.present? && issue.pull_request_id == pull_request_id

    pr = pull_request(pull_request_id, repository_id)
    return [] unless pr.present?

    issue.memex_project_items.
      where("id > ?", offset_item_id).
      order(id: :asc).
      limit(BATCH_SIZE).
      to_a
  end

  sig { params(memex_project_items: T::Array[MemexProjectItem], options: T.untyped).void }
  def process_batch(memex_project_items, **options)
    pull_request_id = T.let(options.fetch(:pull_request_id), Integer)
    repository_id = T.let(options.fetch(:repository_id), Integer)

    pr = pull_request(pull_request_id, repository_id)
    return unless pr.present?

    memex_project_items.each do |item|
      item.content = pr
      MemexProjectItem.throttle do
        with_write { item.save! }
      end
    end
  end

  private

  sig { params(id: Integer, repository_id: Integer).returns(T::nilable(PullRequest)) }
  def pull_request(id, repository_id)
    @pull_request = T.let(PullRequest.find_by(id: id, repository_id: repository_id), T.nilable(PullRequest)) unless defined?(@pull_request)
    @pull_request
  end
end
