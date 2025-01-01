# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# The purpose of this job is to reconcile the state of Repository source
# code between the file servers and the search index. We do this by
# iterating over each Repository, reading the last index commit from the
# search index, and then reconciling any differences with the file
# servers.
#
# Each repair worker will process 100 repositories. When it has reconciled
# all the source code it will enqueue another job. This process will
# continue until all repositories have been reconciled.
#
# To make this whole process faster, multiple repair jobs can be enqueued.
# The current offest into the repositories table is stored in redis.
# Access to this value is coordinated via a shared mutex. Don't spin up
# too many repair jobs otherwise you'll kill the database or the search
# index or both.
class RepairCodeSearchIndexJob < Elastomer::RepairJob
  queue_as :index_bulk

  def perform(name, opts = {})
    return unless GitHub.use_elastomer_code_search?
    super
  end

  def reconcilers
    return @reconcilers if defined?(@reconcilers)

    @reconcilers = [CodeReconciler.new(
      index: index,
      group_key: group_key,
      redis: redis,
    )]
  end

  class CodeReconciler < Elastomer::Reconciler

    LIMIT = GitHub.enterprise? ? 1 : 100

    # Create a new CodeReconciler that will reconcile source code between
    # the file servers and the search index.
    #
    # opts - Options Hash
    def initialize(opts)
      opts = opts.merge \
        type: "repository",
        limit: LIMIT,
        accept: :code_is_searchable?

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
          adapter = Elastomer::Adapters::Code.create(models_hash[id], adapter_args)
          index.store(adapter)
        rescue StandardError, TimeoutError => boom # rubocop:todo Lint/GenericRescue
          Failbot.report(boom.with_redacting!, "gh.repo.id": id)
        end
      end

      unless remove.blank?
        begin
          query = { query: { terms: { repo_id: remove } } }

          index.docs.delete_by_query(query, type: %w[code repository])
        rescue StandardError, TimeoutError => boom # rubocop:todo Lint/GenericRescue
          Failbot.report(boom.with_redacting!)
        end
      end
    end
  end
end
