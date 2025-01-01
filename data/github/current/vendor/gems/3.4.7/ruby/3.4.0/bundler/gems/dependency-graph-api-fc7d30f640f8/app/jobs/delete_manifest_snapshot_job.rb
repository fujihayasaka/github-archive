class DeleteManifestSnapshotJob < RetryJob
  # A PoC to route eligible manifest files (starting with NPM package-lock.json)
  # into DS-API's snapshot ingest upon consumption of RepositoryManifestFileChanged
  # events. In this case, we submit an *empty snapshot* to force DS-API to clean up
  # a snapshot when a manifest file-deleted event is consumed by DG-API

  queue_as do
    ecosystem = Types::PackageManager[:npm].to_s
    :"manifest_snapshots_#{ecosystem}"
  end

  def log_snapshot_summary(event, snapshot)
    DependencyGraph.logger.info("Assembled manifest-delete snapshot submission",
      "gh.dependency_graph.package_manager" => Types::PackageManager[:npm],
      "gh.dependency_graph.manifest.type" => Types::Manifest[:package_lock_json],
      "gh.repo.id" => event[:repository_id],
      "gh.repo.owner_id" => event[:owner_id],
      "gh.repo.name_with_owner" => event[:repository_nwo],
      "gh.dependency_graph.event_type" => "delete",
      "gh.dependency_graph.job_id" => snapshot[:job][:id],
      "gh.dependency_graph.snapshot.job_correlator" => snapshot[:job][:correlator],
      "gh.commit.sha" => snapshot[:sha],
      "gh.git.ref" => snapshot[:ref],
    )
  end

  def perform(hydro_message, log_context = {})
    DependencyGraph.logger.log_and_failbot_context(log_context) do
      cleanup_snapshot = nil
      begin
        cleanup_snapshot = ManifestAdapters::Npm::SnapshotParsers.base_snapshot(hydro_message)
      rescue StandardError => e
        Instrument.increment("etl.manifest_snapshot.parser.error",
                             package_manager: Types::PackageManager[:npm],
                             manifest_type: Types::Manifest[:package_lock_json],
                             event_type: "delete",
                             type: e.class.to_s.downcase)
        DependencyGraph.logger.error("failed to construct snapshot from delete event", e)
        Failbot.report(e)
        return
      end

      log_snapshot_summary(hydro_message, cleanup_snapshot)
      Instrument.increment("etl.manifest_snapshot.loaded",
                           package_manager: Types::PackageManager[:npm],
                           manifest_type: Types::Manifest[:package_lock_json],
                           event_type: "delete")

      # submit well-formed snapshot to DS-API
      dsapi_client = DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient.new

      resp = nil
      Instrument.time_dist("etl.manifest_snapshot.submit") do
        resp = dsapi_client.create_dependency_snapshot(hydro_message[:repository_id], cleanup_snapshot.to_json)
      end

      if resp && resp.error.present?
        DependencyGraph.logger.error("failed to submit delete snapshot to DS-API",
          "exception.message" => resp.error.msg[..500],
          "gh.repo.id" => hydro_message[:repository_id],
          "http.status_code" => resp.error.code,
          "gh.meta" => resp.error.meta)

        Instrument.increment("etl.manifest_snapshot.submit.failed",
                             package_manager: Types::PackageManager[:npm],
                             manifest_type: Types::Manifest[:package_lock_json],
                             event_type: "delete",
                             error_type: resp.error.code.to_s)
        return
      end

      Instrument.increment("etl.manifest_snapshot.submit.success",
                           package_manager: Types::PackageManager[:npm],
                           manifest_type: Types::Manifest[:package_lock_json],
                           event_type: "delete")
    end
  end
end
