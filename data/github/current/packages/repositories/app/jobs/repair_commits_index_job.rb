# typed: true
# frozen_string_literal: true

class RepairCommitsIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  def reconcilers
    return @reconcilers if defined?(@reconcilers)

    @reconcilers = [CommitsReconciler.new(
      index: index,
      group_key: group_key,
      redis: redis,
    )]
  end

  class CommitsReconciler < ::Elastomer::Reconciler

    LIMIT = GitHub.enterprise? ? 1 : 100

    # Create a new CommitsReconciler that will reconcile commits between
    # the file servers and the search index.
    #
    # opts - Options Hash
    def initialize(opts)
      opts = opts.merge \
        type: "repository",
        limit: LIMIT,
        accept: :commits_are_searchable?

      super opts
    end

    # Internal: Perform the bulk indexing operations to bering the search
    # index in sync with the database records.
    #
    # upsert - Array of model IDs to update / add
    # remove - Array of model IDs to remove
    # metadata - Hash of metadata information for each Elasticsearch document
    #
    # Returns the result of the bulk indexing operation.
    def update_search_index(upsert, remove, metadata)
      models_hash = models.index_by(&:id)

      upsert.each do |id|
        begin
          adapter = Elastomer::Adapters::Commit.create(models_hash[id], adapter_args)
          index.store(adapter)
        rescue ElastomerClient::Client::TimeoutError => boom
          Failbot.report(boom, "gh.repo.id": id)
        end
      end

      unless remove.blank?
        begin
          query = { query: { terms: { repo_id: remove } } }

          index.docs.delete_by_query(query, type: %w[commit repository])
        rescue ElastomerClient::Client::TimeoutError => boom
          Failbot.report boom
        end
      end
    end
  end
end
