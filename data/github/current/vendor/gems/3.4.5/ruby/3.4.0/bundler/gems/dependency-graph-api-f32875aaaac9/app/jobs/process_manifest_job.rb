# frozen_string_literal: true

class ProcessManifestJob < RetryJob
  include DependencyGraph::Tracing

  trace_method :get_manifest_blob, span_attribute_extractor: -> (_instance, *args, **_kwargs) { ProcessManifestJob.tags_for_message(args[0]) }
  trace_method :parse_manifest, span_attribute_extractor: -> (_instance, *args, **_kwargs) { ProcessManifestJob.tags_for_message(args[0]) }

  queue_as { :"manifest_#{package_manager}" }

  def self.tags_for_message(manifest_update_message)
    {
      "gh.repo.id" => manifest_update_message[:repository_id],
      "gh.repo.name_with_owner" => manifest_update_message[:repository_nwo],
      "gh.repo.owner.id" => manifest_update_message[:owner_id],
      "gh.dependency_graph.manifest.path" => manifest_update_message[:manifest_file][:path],
      "gh.dependency_graph.manifest.filename" => manifest_update_message[:manifest_file][:filename],
    }
  end

  def otel_tags
    message = self.arguments.first
    ProcessManifestJob.tags_for_message(message).merge({
      "gh.dependency_graph.package_manager": package_manager.to_s,
    })
  end

  def package_manager
    message = self.arguments.first
    ManifestAdapters.recognize(
      filename: message[:manifest_file][:filename],
      path: message[:manifest_file][:path]
    )&.package_manager
  end

  def stats_tags
    ["package_manager:#{package_manager}"]
  end

  def perform(manifest_update_message, log_context: {})
    DependencyGraph.logger.with_named_tags(otel_tags.merge(log_context)) do
      if Ingest::Blocklist.blocklisted_manifest?({
        github_repository_id: manifest_update_message[:repository_id],
        repository_nwo: manifest_update_message[:repository_nwo]
      })
        DependencyGraph.logger.info(
          "Skipping blocklisted manifest",
        )
        return
      end

      content = get_manifest_blob(manifest_update_message)

      DependencyGraph.logger.with_named_tags({
        "gh.dependency_graph.manifest_length": content.length,
       }) do

        manifest = parse_manifest(manifest_update_message, content)

        # Skip nil manifests to prevent head-of-line blocking.
        if manifest.nil?
          # More verbose logging is already in the self.parse_manifest
          DependencyGraph.logger.info("Skipping nil manifest")
          Instrument.increment("process_manifest.skipping_nil_manifest",
            package_manager: package_manager.to_s
          )
          return
        end

        if manifest.manifest_type == Types::Manifest[:unknown]
          DependencyGraph.logger.info("Skipping unknown manifest type")
          Instrument.increment("process_manifest.skipping_unknown_manifest_type",
            package_manager: package_manager.to_s
          )
          return
        end

        DependencyGraph.logger.with_named_tags({
          "gh.dependency_graph.manifest.is_backfill": manifest.is_backfill,
          "gh.dependency_graph.manifest.type": manifest.manifest_type,
          "gh.dependency_graph.package_manager": manifest.package_manager,
        }) do
          loader = Ingest::ManifestLoader.new(manifest)
          loaded_manifest = loader.load
          Instrument.increment("process_manifest.manifest_processed",
            package_manager: manifest.package_manager,
            manifest_type: manifest.manifest_type,
            manifest_load_success: loaded_manifest.present?
          )
          DependencyGraph.logger.info("Loaded manifest")
          Instrument.increment("etl.ingest.processed", stage: "manifests", package_manager: manifest.package_manager)
        end
      end
    end
  end

  private

  ##
  # Given a message from the job, returns the contents of a manifest file from the repository.
  def get_manifest_blob(message)
    repository_id = message[:repository_id]
    blob_oid = message[:manifest_file][:blob_oid]
    filename = message[:filename]

    if (Rails.env.development? || Rails.env.test?) && !message[:manifest_contents].nil?
      DependencyGraph.logger.info("Manifest contents was attached to the message, skipping call to Spokes",
        "deployment.environment" => Rails.env,
      )
      return message[:manifest_contents]
    end

    content = nil

    get_blob_time = Benchmark.measure do
      blob = blob_provider.get_blob(repository_id: repository_id, oid: blob_oid)
      content = blob.content

      # Git (and Spokes response payloads) deal in byte blobs, and don't enforce UTF-8 encoding.
      # We need to make sure that the content is UTF-8 encoded, but for content that is already UTF-8 (e.g. string literals in tests)
      # we avoid the force_encoding step.
      content = content.to_s
      if content.encoding != Encoding::UTF_8
        forced_utf8 = content.force_encoding(Encoding::UTF_8).scrub
        if forced_utf8 != content
          # if we scrubbed any characters out, emit a metric
          Instrument.increment("process_manifest.manifest_contents_invalid_utf8_character",
                                file: filename.to_s)
          content = forced_utf8
        end
      end
      content
    end

    get_blob_time_ms = (get_blob_time.real * 1000).floor
    DependencyGraph.logger.info(
      "Fetched manifest blob",
      "gh.dependency_graph.blob_operations.get_manifest_blob_time" => get_blob_time_ms,
    )

    content
  end

  ##
  # Given a message from the job and the contents of the manifest, parses and returns a manifest object.
  def parse_manifest(message, content)
    adapter = ManifestAdapters.recognize(
      filename: message[:manifest_file][:filename],
      path: message[:manifest_file][:path]
    )

    return nil if adapter.nil?

    manifest_type = adapter.manifest_type(
      filename: message[:manifest_file][:filename],
      path: message[:manifest_file][:path]
    )

    Instrument.increment("process_manifest.recognized_manifest",
                          package_manager: adapter.package_manager,
                          manifest_type: manifest_type)

    manifest = nil
    manifest_parse_time = Benchmark.measure do
      pushed_at = Time.at(message[:manifest_file][:pushed_at][:seconds] || Time.now.to_i).to_datetime
      manifest = adapter.parse(
        filename: message[:manifest_file][:filename],
        path: message[:manifest_file][:path],
        content: content,
        git_ref: message[:manifest_file][:git_ref],
        pushed_at: pushed_at,
        github_repository_id: message[:repository_id],
        github_owner_id: message[:owner_id],
        repository_nwo: message[:repository_nwo],
        repository_stargazer_count: message[:repository_stargazer_count],
        visibility_private: message[:repository_private],
        fork: message[:repository_fork],
        is_backfill: message[:is_backfill]
      )
    end
    manifest_parse_time_ms = (manifest_parse_time.real * 1000).floor

    Instrument.distribution("process_manifest.manifest_parse_time", manifest_parse_time_ms,
      package_manager: adapter.package_manager,
      manifest_type: manifest.manifest_type
    )
    DependencyGraph.logger.info(
      "Parsed manifest",
      "gh.dependency_graph.manifest.parse_time": manifest_parse_time_ms,
    )

    manifest
  rescue StandardError => e
    Instrument.increment("process_manifest.parse_manifest_error",
      package_manager: adapter.package_manager,
      error: e.class.to_s
    )
    Failbot.report(e)
    nil
  end

  def blob_provider
    @blob_provider ||= BlobOperations::Spokes::Client.new
  end
end
