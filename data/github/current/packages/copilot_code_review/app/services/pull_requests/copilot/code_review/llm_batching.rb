# typed: true
# frozen_string_literal: true

# Shared batching helper for LLM calls in the recall and precision analyzers.
# Breaks concurrent Promise.all calls into smaller batches with pauses
# to stay under CAPI's per-user rate limit (api-global-ratelimit: 30 RPM).
module PullRequests::Copilot::CodeReview::LlmBatching
  LLM_BATCH_SIZE = 5
  LLM_BATCH_DELAY_SECONDS = 2

  # Run LLM calls in batches. The first call in each batch runs synchronously
  # to allow prompt caching; the rest fire concurrently within the batch.
  # A brief sleep between batches reduces burst impact on the shared per-user
  # rate limit.
  #
  # Returns an array of results in the same order as items.
  def run_llm_batched(items)
    results = []
    total_batches = (items.size.to_f / LLM_BATCH_SIZE).ceil

    items.each_slice(LLM_BATCH_SIZE).with_index do |batch, batch_idx|
      first_item, *rest = batch

      results << yield(T.must(first_item)).sync

      unless rest.empty?
        promises = rest.map { |item| yield(item) }
        results.concat(Promise.all(promises).sync)
      end

      Kernel.sleep(LLM_BATCH_DELAY_SECONDS) if batch_idx < total_batches - 1
    end

    results
  end
end
