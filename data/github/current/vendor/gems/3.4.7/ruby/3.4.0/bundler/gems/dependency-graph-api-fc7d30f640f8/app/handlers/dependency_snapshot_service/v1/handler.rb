require File.join(Rails.root, "lib/dependency_snapshots_api/snapshots_client")

module DependencySnapshotService
  module V1
    class Handler < TracedHandler
      def initialize(snapshots_client: default_snapshots_client)
        @snapshots_client = snapshots_client
      end
      attr_accessor :snapshots_client

      def default_snapshots_client
        DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient.new
      end

      def create_dependency_snapshot(req, env)
        trace(
          **get_tracing_payload_from_create_request(req)
        )

        DependencyGraph.logger.info("Received create_dependency_snapshot request",
                                   **get_tracing_payload_from_create_request(req))

        result = validate_create_params(req)
        return twirp_400(fields: result[:missing_fields]) unless result[:params_present]
        return twirp_404 if !DependencyGraphAPI.snapshots_enabled?

        # proxy the submission over to DS-API
        ds_resp = {}
        Instrument.time_dist("dependency_snapshot_handler.create_dependency_snapshot.proxy_to_dsapi") do
          ds_resp = snapshots_client.create_dependency_snapshot(req.repository_id, req.payload)
        end

        if ds_resp.error
          return Twirp::Error.new(ds_resp.error.code, ds_resp.error.msg, ds_resp.error.meta)
        end

        # return the response to the caller
        DependencyGraphAPI::V1::CreateDependencySnapshotResponse.new(
          snapshot_id: ds_resp.data.snapshot_id,
          created_at: ds_resp.data.created_at,
          result: ds_resp.data.result,
          message: ds_resp.data.message,
        )
      end

      def get_dependency_snapshot(req, env)
        trace(
          **get_tracing_payload_from_get_request(req)
        )

        result = validate_read_params(req)
        return twirp_400(fields: result[:missing_fields]) unless result[:params_present]
        return twirp_404 if !DependencyGraphAPI.snapshots_enabled?

        DependencyGraph.logger.info("Received get_dependency_snapshot request",
                                    **get_tracing_payload_from_get_request(req))

        # proxy the submission over to DS-API
        ds_resp = {}
        Instrument.time_dist("dependency_snapshot_handler.get_dependency_snapshot.proxy_to_dsapi") do
          ds_resp = snapshots_client.get_dependency_snapshot(req.repository_id, req.snapshot_id)
        end

        if ds_resp.error
          return Twirp::Error.new(ds_resp.error.code, ds_resp.error.msg, ds_resp.error.meta)
        end

        # return response to the caller
        DependencyGraphAPI::V1::GetDependencySnapshotResponse.new(
          repository_id: ds_resp.data.repository_id,
          snapshot_id: ds_resp.data.snapshot_id,
          payload: ds_resp.data.payload
        )
      end

      def get_included_dependency_snapshots(req, env)
        trace(
          **get_tracing_payload_from_get_included_request(req)
        )

        result = validate_get_included_params(req)
        return twirp_400(fields: result[:missing_fields]) unless result[:params_present]
        return twirp_404 if !DependencyGraphAPI.snapshots_enabled?

        DependencyGraph.logger.info("Received get_included_dependency_snapshots request",
          **get_tracing_payload_from_get_included_request(req))

        # proxy the request over to DS-API
        ds_resp = snapshots_client.get_included_dependency_snapshots(req.repository_id)

        if ds_resp.error
          return Twirp::Error.new(ds_resp.error.code, ds_resp.error.msg, ds_resp.error.meta)
        end

        snapshots = ds_resp.data.included_snapshots.map do |snapshot|
          DependencyGraphAPI::V1::GetIncludedDependencySnapshotsResponse::IncludedSnapshot.new(
            snapshot_id: snapshot.snapshot_id,
            correlator: snapshot.correlator,
            detector: snapshot.detector
          )
        end

        DependencyGraphAPI::V1::GetIncludedDependencySnapshotsResponse.new(
          included_snapshots: snapshots
        )
      end

      def exclude_dependency_snapshots(req, env)
        trace(
            **get_tracing_payload_from_exclude_snapshots_request(req)
          )
        result = validate_exclude_snapshots_params(req)
        return twirp_400(fields: result[:missing_fields]) unless result[:params_present]
        return twirp_404 if !DependencyGraphAPI.snapshots_enabled?

          # proxy the request over to DS-API
        ds_resp = snapshots_client.exclude_dependency_snapshots(req.repository_id, req.snapshot_ids.to_a)
        if ds_resp.error
          return Twirp::Error.new(ds_resp.error.code, ds_resp.error.msg, ds_resp.error.meta)
        end
          # return response to the caller
        DependencyGraphAPI::V1::ExcludeDependencySnapshotsResponse.new(
          excluded_snapshot_ids: ds_resp.data.excluded_snapshot_ids.to_a
        )
      end

      add_log_context :create_dependency_snapshot
      add_log_context :get_dependency_snapshot

      private

      # TODO: more request/snapshot meta; skipping for now to avoid deserialization before trace
      def get_tracing_payload_from_create_request(req)
        {
          "gh.repo.id" => req.repository_id
        }
      end

      def get_tracing_payload_from_get_request(req)
        {
          "gh.repo.id" => req.repository_id,
          "gh.dependency_graph.snapshot.id" => req.snapshot_id
        }
      end

      def get_tracing_payload_from_get_included_request(req)
        {
          "gh.repo.id" => req.repository_id
        }
      end

      def get_tracing_payload_from_exclude_snapshots_request(req)
        {
          "gh.repo.id" => req.repository_id,
          "gh.dependency_graph.snapshot.ids" => req.snapshot_ids.to_a
        }
      end

      # required payload fields are validated upstream in the dotcom
      # create_dependency_snapshot API, and can be updated there.
      def validate_create_params(req)
        missing_fields = []
        missing_fields.push(:repository_id) unless is_property_present(obj: req, symbol: :repository_id)
        missing_fields.push(:payload) unless is_property_present(obj: req, symbol: :payload)
        missing_fields.push(:repository_metadata) unless is_property_present(obj: req, symbol: :repository_metadata)

        {
          params_present: missing_fields.empty?,
          missing_fields: missing_fields
        }
      end

      # TODO: flesh this out when we evolve past fetch-by-id stage
      def validate_read_params(req)
        missing_fields = []
        missing_fields.push(:snapshot_id) unless is_property_present(obj: req, symbol: :snapshot_id)
        missing_fields.push(:repository_id) unless is_property_present(obj: req, symbol: :repository_id)

        {
          params_present: missing_fields.empty?,
          missing_fields: missing_fields
        }
      end

      def validate_get_included_params(req)
        missing_fields = []
        missing_fields.push(:repository_id) unless is_property_present(obj: req, symbol: :repository_id)

        {
          params_present: missing_fields.empty?,
          missing_fields: missing_fields
        }
      end

      def validate_exclude_snapshots_params(req)
        missing_fields = []
        missing_fields.push(:repository_id) unless is_property_present(obj: req, symbol: :repository_id)
        missing_fields.push(:snapshot_ids) unless is_property_present(obj: req, symbol: :snapshot_ids)

        {
          params_present: missing_fields.empty?,
          missing_fields: missing_fields
        }
      end

      # TODO: update legacy diff req/resp format; broken for now
      def diff_params_present(req)
        missing_fields = []
        missing_fields.push(:base_repository_id) unless is_property_present(obj: req, symbol: :base_repository_id)

        is_base_filter_present = is_property_present(obj: req, symbol: :base_build_type) && is_property_present(obj: req, symbol: :base_build_id)
        is_base_filter_present ||= is_property_present(obj: req, symbol: :base_snapshot_id)
        missing_fields.push("base_snapshot_id OR (base_build_type AND base_build_id)") unless is_base_filter_present

        is_target_filter_present = is_property_present(obj: req, symbol: :target_build_type) && is_property_present(obj: req, symbol: :target_build_id)
        is_target_filter_present ||= is_property_present(obj: req, symbol: :target_snapshot_id)
        missing_fields.push("target_snapshot_id OR (target_build_type AND target_build_id)") unless is_target_filter_present

        {
          params_present: missing_fields.empty?,
          missing_fields: missing_fields
        }
      end

      def get_diff_tracing_payload_from_request(req)
        {
          "gh.dependency_graph.snapshot.diff.base.repo_id" => req.base_repository_id,
          "gh.dependency_graph.snapshot.diff.target.repo_id" => req.target_repository_id,
          "gh.dependency_graph.snapshot.diff.base.snapshot_id" => req.base_snapshot_id,
          "gh.dependency_graph.snapshot.diff.target.snapshot_id" => req.target_snapshot_id,
          "gh.dependency_graph.snapshot.diff.base.ref" => req.base_ref,
          "gh.dependency_graph.snapshot.diff.target.ref" => req.target_ref,
          "gh.dependency_graph.snapshot.diff.base.sha" => req.base_sha,
          "gh.dependency_graph.snapshot.diff.target.sha" => req.target_sha,
          "gh.dependency_graph.snapshot.diff.base.build_type" => req.base_build_type,
          "gh.dependency_graph.snapshot.diff.target.build_type" => req.target_build_type,
          "gh.dependency_graph.snapshot.diff.base.build_id" => req.base_build_id,
          "gh.dependency_graph.snapshot.diff.target.build_id" => req.target_build_id
        }
      end
    end
  end
end
