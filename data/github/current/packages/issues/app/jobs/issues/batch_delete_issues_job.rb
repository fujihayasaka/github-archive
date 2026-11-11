# typed: strict
# frozen_string_literal: true

module Issues
  class BatchDeleteIssuesJob < BatchedJob
    # This job was written for SIRT mitigation.
    queue_as :spam

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    # expecting options to have:
    # :issue_ids as array of issue id (integers)
    # :actor_id as actor id (integer)
    sig do
      params(
        args: T.untyped,
        timestamp: T.nilable(Time),
        offset_item_id: T.nilable(Integer),
        progress: T.nilable(Integer),
        options: T.untyped
      ).returns(T.any(T::Array[Issue], ActiveRecord::Relation))
    end
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      Issue
        .where(id: options[:issue_ids].sort.select { |id| id > offset_item_id })
        .where("id > ?", offset_item_id)
        .order(id: :asc)
        .limit(BATCH_SIZE)
    end

    sig { params(requests: T.any(T::Array[Issue], ActiveRecord::Relation), args: T.untyped, options: T.untyped).void }
    def process_batch(requests, *args, **options)
      actor = User.find(options[:actor_id])
      with_write do
        requests.each do |issue|
          o = IssueOrchestration.delete_issue(issue: issue, actor: actor)
          o.execute
        end
      end
    end
  end
end
