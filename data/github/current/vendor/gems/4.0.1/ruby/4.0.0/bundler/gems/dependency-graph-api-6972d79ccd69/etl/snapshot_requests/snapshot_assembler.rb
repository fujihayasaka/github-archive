require "concurrent"
require "concurrent/promises"

module SnapshotRequests
  class SnapshotAssembler
    # Concurrency tuning constants for blob fetching
    CONCURRENT_BLOB_P95_THRESHOLD = 20
    # Number of blobs to fetch in parallel per chunk
    CONCURRENT_BLOB_CHUNK_SIZE = 10

    INSTRUMENTATION_PREFIX = "etl.snapshot.assembler".freeze
    IGNORE_JS = true # do not attempt to identify random potential vendored javascript files

    attr_reader :blob_operations_provider

    def initialize(blob_operations_provider)
      @blob_operations_provider = blob_operations_provider
    end

    def assemble_snapshot(snapshot_request)
      Instrument.time("#{INSTRUMENTATION_PREFIX}.assemble_snapshot.time", **tags) do
        if snapshot_request[:tree].nil?
          assemble_complete_snapshot(snapshot_request)
        else
          assemble_sparse_snapshot(snapshot_request)
        end
      end
    end

    private
    def assemble_complete_snapshot(snapshot_request)
      Instrument.time("#{INSTRUMENTATION_PREFIX}.assemble_complete_snapshot.time", **tags) do
        file_tree = get_tree(snapshot_request)
        manifest_entries = get_manifest_entries(file_tree)
        Instrument.histogram(
          "#{INSTRUMENTATION_PREFIX}.assemble_complete_snapshot.manifests",
          manifest_entries.count,
          **tags
        )
        manifest_blobs = get_manifest_blobs(snapshot_request, manifest_entries)
        dependency_snapshot_from_blobs(snapshot_request, manifest_blobs)
      end
    end

    def assemble_sparse_snapshot(snapshot_request)
      Instrument.time("#{INSTRUMENTATION_PREFIX}.assemble_sparse_snapshot.time", **tags) do
        file_tree = tree_from_request(snapshot_request[:tree])
        manifest_entries = get_manifest_entries(file_tree)
        Instrument.histogram(
          "#{INSTRUMENTATION_PREFIX}.assemble_sparse_snapshot.manifests",
          manifest_entries.count,
          **tags
        )
        manifest_blobs = get_manifest_blobs(snapshot_request, manifest_entries)
        dependency_snapshot_from_blobs(snapshot_request, manifest_blobs)
      end
    end

    # Slightly hacky way to construct something _close enough_ to a TreeResponse
    RequestTreeEntry = Struct.new(:path, :oid)
    RequestTree = Struct.new(:tree_entries)

    def tree_from_request(changed_files)
      entries = changed_files.map do |file|
        RequestTreeEntry.new(file.path, file.blob_id)
      end
      RequestTree.new(entries)
    end

    def get_tree(snapshot_request)
      Instrument.time("#{INSTRUMENTATION_PREFIX}.get_tree.time", **tags) do
        blob_operations_provider.get_tree(
          repository_id: snapshot_request[:repository][:id],
          commit_id: snapshot_request[:sha],
          quality_of_service: :QUALITY_OF_SERVICE_NO_DELAY
        )
      end
    end

    def get_manifest_entries(file_tree)
      filtered_tree_entries = file_tree.tree_entries.filter do |tree_entry|
        if ManifestAdapters.recognized_path?(path: tree_entry.path)
          !IGNORE_JS || ManifestAdapters.manifest_type(path: tree_entry.path) != Types::Manifest[:vendored_javascript_dependency]
        end
      end
      filtered_tree_entries.map { |manifest| [manifest.oid, manifest] }
    end

    def get_manifest_blobs(snapshot_request, manifest_entries, processed_blobs: {})
      manifest_count = manifest_entries.size
      repository_id = snapshot_request[:repository][:id]

      if should_fetch_concurrently?(manifest_count, repository_id)
        fetch_blobs_concurrently(snapshot_request, manifest_entries, processed_blobs)
      else
        fetch_blobs_sequentially(snapshot_request, manifest_entries, processed_blobs)
      end
    end

    def should_fetch_concurrently?(manifest_count, _repository_id)
      manifest_count > CONCURRENT_BLOB_P95_THRESHOLD
    end

    def fetch_blobs_sequentially(snapshot_request, manifest_entries, processed_blobs)
      Instrument.time("#{INSTRUMENTATION_PREFIX}.get_all_manifest_blobs.time", **tags) do
        manifest_entries.map do |manifest_id, manifest_entry|
          blob = processed_blobs[manifest_id] || get_manifest_blob(snapshot_request, manifest_entry)
          [manifest_id, blob]
        end.to_h
      end
    end

    def fetch_blobs_concurrently(snapshot_request, manifest_entries, processed_blobs)
      concurrent_tags = tags.merge({
        concurrent_fetch: true
      })

      Instrument.time("#{INSTRUMENTATION_PREFIX}.get_all_manifest_blobs.time", **concurrent_tags) do
        chunk_count = (manifest_entries.size.to_f / CONCURRENT_BLOB_CHUNK_SIZE).ceil
        Instrument.count("#{INSTRUMENTATION_PREFIX}.concurrent_blob_fetch.chunk_count", chunk_count, **tags)

        results = {}

        manifest_entries.each_slice(CONCURRENT_BLOB_CHUNK_SIZE) do |chunk|
          futures = chunk.map do |manifest_id, manifest_entry|
            next if processed_blobs[manifest_id]

            Concurrent::Promises.future do
              [manifest_id, get_manifest_blob(snapshot_request, manifest_entry)]
            end
          end.compact

          chunk_results = futures.map(&:value!)
          chunk_results.each { |manifest_id, blob| results[manifest_id] = blob }
        end

        # Merge with any pre-processed blobs
        processed_blobs.merge(results)
      end
    end

    def get_manifest_blob(snapshot_request, manifest_entry)
      return nil if manifest_entry.nil?

      blob_data = get_blob(snapshot_request, manifest_entry.oid)

      {
        oid: manifest_entry.oid,
        path: manifest_entry.path,
        content: blob_data.content
      }
    end

    def get_blob(snapshot_request, blob_oid)
      Instrument.time("#{INSTRUMENTATION_PREFIX}.get_blob.time", **tags) do
        blob_operations_provider.get_blob(
          repository_id: snapshot_request[:repository][:id],
          oid: blob_oid
        )
      end
    end

    def dependency_snapshot_from_blobs(snapshot_request, manifest_blobs)
      Instrument.time("#{INSTRUMENTATION_PREFIX}.dependency_snapshot.time", **tags) do
        manifests = manifest_blobs.map do |manifest_id, manifest_blob|
          get_dependency_manifest_from_blob(snapshot_request, manifest_blob) unless manifest_blob.nil?
        end

        Snapshots::Snapshot.new(
          metadata: Snapshots::Metadata.new(
            push_id: snapshot_request[:push_id],
            sha: snapshot_request[:sha],
            ref: snapshot_request[:ref]
          ),
          github_repository_id: snapshot_request[:repository][:id],
          manifests: manifests,
          source: @blob_operations_provider.name
        )
      end
    end

    def get_dependency_manifest_from_blob(snapshot_request, manifest_blob)
      path = manifest_blob[:path]
      dir, filename = File.dirname(path), File.basename(path)

      Instrument.time("#{INSTRUMENTATION_PREFIX}.dependency_parsing.time", **tags) do
        manifest = ManifestAdapters.parse(
          filename:                   filename,
          path:                       dir,
          content:                    manifest_blob[:content],
          git_ref:                    snapshot_request[:ref],
          github_repository_id:       snapshot_request[:repository][:id],
          github_owner_id:            snapshot_request[:repository][:owner_id],
          repository_stargazer_count: snapshot_request[:repository][:stargazer_count],
          pushed_at:                  snapshot_request[:pushed_at],
          fork:                       nil,
          visibility_private:         nil
        )

        dependencies = manifest.dependencies.map do |manifest_dependency|
          Snapshots::Dependency.new(
            name: manifest_dependency.package_name,
            version: manifest_dependency.requirements || manifest_dependency.raw_requirements,
            scope: manifest_dependency.scope
          )
        end

        Snapshots::Manifest.new(
          path: path,
          oid: manifest_blob[:oid],
          dependencies: dependencies
        )
      end
    end

    def tags
      @tags ||= {
        provider: blob_operations_provider.name
      }
    end
  end
end
