class LoadManifestSnapshotJob < RetryJob
  # A PoC to route eligible manifest files (starting with NPM package-lock.json)
  # into DS-API's snapshot ingest upon consumption of RepositoryManifestFileChanged
  # events

  queue_as do
    ecosystem = Types::PackageManager[:npm].to_s
    :"manifest_snapshots_#{ecosystem}"
  end

  def log_snapshot_summary(event, snapshot)
    manifest_files = snapshot[:manifests].keys.join(",")
    DependencyGraph.logger.info(
      "Parsed manifest into snapshot submission", {
        "gh.dependency_graph.event_type" => "change",
        "gh.dependency_graph.manifest.files" => manifest_files,
        "gh.dependency_graph.snapshot.job_id" => snapshot[:job][:id],
        "gh.dependency_graph.snapshot.job_correlator" => snapshot[:job][:correlator],
        "gh.dependency_graph.snapshot.sha" => snapshot[:sha],
        "gh.dependency_graph.snapshot.ref" => snapshot[:ref],
      }
    )
  end

  def fetch_content(event, manifest_path, manifest_filename, blob_oid)
    content = nil
    DependencyGraph.logger.with_named_tags(
      {
        "gh.blob_oid" => blob_oid,
        "gh.dependency_graph.manifest.path" => manifest_path,
        "gh.dependency_graph.manifest.filename" => manifest_filename,
      }
    ) do
      get_blob_time = Benchmark.measure do
        blob = spokes_client.get_blob(repository_id: event[:repository_id], oid: blob_oid)
        content = blob&.content.to_s

        # Git (and Spokes response payloads) deal in byte blobs, and don't enforce UTF-8 encoding.
        # We need to make sure that the content is UTF-8 encoded, but for content that is already UTF-8 (e.g. string literals in tests)
        # we avoid the force_encoding step.
        if content.encoding != Encoding::UTF_8
          forced_utf8 = content.force_encoding(Encoding::UTF_8).scrub
          if forced_utf8 != content
            # if we scrubbed any characters out, emit a metric
            Instrument.increment("etl.manifest_snapshot.contents_invalid_utf8_character", file: manifest_filename.to_s)
            content = forced_utf8
          end
        end
      end
      get_blob_time_ms = (get_blob_time.real * 1000).floor

      DependencyGraph.logger.info(
        "Obtained content for snapshot manifest blob", {
          "gh.dependency_graph.load_manifest_snapshot_job.fetch_content.time_ms" => get_blob_time_ms,
        }
      )

      content

    rescue StandardError => e
      Instrument.increment("etl.manifest_snapshot.fetch_content.error",
                           package_manager: Types::PackageManager[:npm],
                           manifest_type: Types::Manifest[:package_lock_json],
                           method: "fetch_content",
                           type: e.class.to_s.downcase)
      DependencyGraph.logger.error("Failed to fetch snapshot manifest blob content from Spokes", e)
      Failbot.report(e)
      raise e
    end
  end

  def spokes_client
    return @spokes_client if defined?(@spokes_client)
    @spokes_client = BlobOperations::Spokes::Client.new
  end

  def snapshots_client
    return @snapshots_client if defined?(@snapshots_client)

    # define client including custom sentinel header for DS-API metrics faceting
    @snapshots_client = DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient.new
    @snapshots_client.connection.headers["X-GITHUB-DG-INTERNAL-SNAPSHOT"] = "true"

    @snapshots_client
  end

  def perform(hydro_message, log_context = {})
    log_context = log_context.merge(
      {
        "gh.dependency_graph.package_manager" => Types::PackageManager[:npm],
        "gh.dependency_graph.manifest.type" => Types::Manifest[:package_lock_json],
        "gh.repo.id" => hydro_message[:repository_id],
        "gh.repo.owner_id" => hydro_message[:owner_id],
        "gh.repo.name_with_owner" => hydro_message[:repository_nwo],
      })

    DependencyGraph.logger.with_named_tags(log_context) do
      snapshot = nil

      begin
        lockfile_oid = hydro_message.dig(:manifest_file, :blob_oid)
        lockfile_path = hydro_message.dig(:manifest_file, :path)
        lockfile_name = hydro_message.dig(:manifest_file, :filename)
        lockfile_content = fetch_content(hydro_message, lockfile_path, lockfile_name, lockfile_oid)

        manifest_oid = hydro_message.dig(:snapshot_metadata, :associated_manifest, :blob_oid)
        if manifest_oid
          manifest_path = hydro_message.dig(:snapshot_metadata, :associated_manifest, :path)
          manifest_filename = hydro_message.dig(:snapshot_metadata, :associated_manifest, :filename)
          manifest_content = fetch_content(hydro_message, manifest_path, manifest_filename, manifest_oid)
        end

        parser = ManifestAdapters::Npm::SnapshotParsers::PackageLockJson.new(
          content: lockfile_content,
          associated_content: manifest_content,
          hydro_message: hydro_message)

        # parse manifest content and Hydro event meta into a snpashot payload
        snapshot = parser.parse.snapshot
      rescue StandardError => e
        Instrument.increment("etl.manifest_snapshot.parser.error",
                             package_manager: Types::PackageManager[:npm],
                             manifest_type: Types::Manifest[:package_lock_json],
                             event_type: "change",
                             type: e.class.to_s.downcase)
        DependencyGraph.logger.error("failed to parse manifest into snapshot", e)
        Failbot.report(e)
        return
      end

      log_snapshot_summary(hydro_message, snapshot)
      Instrument.increment("etl.manifest_snapshot.loaded",
                           package_manager: Types::PackageManager[:npm],
                           manifest_type: Types::Manifest[:package_lock_json],
                           event_type: "change")

      resp = nil
      Instrument.time_dist("etl.manifest_snapshot.submit") do
        resp = snapshots_client.create_dependency_snapshot(hydro_message[:repository_id], snapshot.to_json)
      end

      if resp && resp.error.present?
        DependencyGraph.logger.error(
          "failed to submit snapshot to DS-API", {
            "twirp.error.msg" => resp.error.msg,
            "twirp.error.code" => resp.error.code,
            "twirp.error.meta" => resp.error.meta
          }
        )

        Instrument.increment("etl.manifest_snapshot.submit.failed",
                             package_manager: Types::PackageManager[:npm],
                             manifest_type: Types::Manifest[:package_lock_json],
                             event_type: "change",
                             error_type: resp.error.code.to_s)
        return
      end

      Instrument.increment("etl.manifest_snapshot.submit.success",
                           package_manager: Types::PackageManager[:npm],
                           manifest_type: Types::Manifest[:package_lock_json],
                           event_type: "change")
    end
  end
end
