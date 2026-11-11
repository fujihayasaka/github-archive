# typed: true
# frozen_string_literal: true

# Performs a partial ES update for a pull request, updating only the fields
# relevant to the given UpdateScope. This avoids the full document rebuild
# (including expensive Spokes/git RPC calls) that AddToSearchIndexJob performs.
#
# Only enqueued when the scope's feature flag is confirmed enabled
# (checked in PullRequest#synchronize_search_index via partial_update_enabled_for_scope?).
class PartialSearchIndexUpdateJob < ApplicationJob
  queue_as :index_high
  retry_on_dirty_exit

  sig { params(pull_request_id: Integer, update_scope: String).void }
  def perform(pull_request_id, update_scope)
    begin
      scope = Elastomer::Adapters::PullRequest::UpdateScope.deserialize(update_scope)
    rescue KeyError
      GitHub.dogstats.increment("pull_requests.partial_search_index_update.skipped", tags: ["reason:invalid_update_scope"])
      return
    end

    adapter = Elastomer::Adapters::PullRequest.create(pull_request_id)

    pr = adapter.pr
    unless pr&.repository
      GitHub.dogstats.increment("pull_requests.partial_search_index_update.skipped", tags: ["reason:missing_model"])
      return
    end

    fields = adapter.partial_hash(scope)
    unless fields.present?
      GitHub.dogstats.increment("pull_requests.partial_search_index_update.skipped", tags: ["reason:empty_fields"])
      return
    end

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    index_class = Elastomer.env.lookup_index(adapter)
    Elastomer.each_writable_index(index_class, adapter) do |config|
      index = index_class.new(config.name, config.cluster)
      index.partial_update(adapter.document_id, fields, routing: adapter.document_routing)
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1_000).to_i
    scope_tag = "scope:#{scope.serialize}"
    GitHub.dogstats.distribution("pull_requests.partial_search_index_update.duration_ms", elapsed_ms, tags: [scope_tag])
    GitHub.dogstats.increment("pull_requests.partial_search_index_update.performed", tags: [scope_tag])
  end
end
