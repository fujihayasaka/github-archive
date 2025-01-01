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
class RepairWikisIndexJob < Elastomer::RepairJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :index_bulk

  def reconcilers
    return @reconcilers if defined?(@reconcilers)

    @reconcilers = [WikiReconciler.new(
      index: index,
      group_key: group_key,
      redis: redis,
    )]
  end

  class WikiReconciler < Elastomer::Reconciler

    # Create a new WikiReconciler that will reconcile wikis and the search
    # index.
    #
    # opts - Options Hash
    def initialize(options)
      opts = options.merge({
        type: "repository",
        limit: 100,
        accept: :wiki_is_searchable?,
      })

      super opts
    end

    # Internal: Perform the bulk indexing operations to bring the search
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
        Failbot.push "gh.repo.id": id
        begin
          adapter = Elastomer::Adapters::Wiki.create(models_hash[id], adapter_args)
          index.store(adapter)
        rescue Elastomer::Error, ElastomerClient::Error => boom
          Failbot.report boom
        end
        Failbot.pop
      end

      unless remove.blank?
        begin
          index.remove_wikis(remove)
        rescue Elastomer::Error, ElastomerClient::Error => boom
          Failbot.report boom
        end
      end
    end
  end
end
