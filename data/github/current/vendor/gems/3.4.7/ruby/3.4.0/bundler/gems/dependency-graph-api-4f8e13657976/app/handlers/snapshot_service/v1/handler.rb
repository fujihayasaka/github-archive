require "dependency_snapshots_api/snapshots_client"
require "dependency_graph/object_model/object_model"

module SnapshotService
  module V1
    class Handler < TracedHandler
      include DependencyGraph::Tracing

      MAX_MANIFESTS_PER_PAGE = 1000

      def initialize(blob_operations_provider: default_blob_operations_provider, snapshots_client: default_snapshots_client)
        @blob_operations_provider = blob_operations_provider
        @snapshots_client = snapshots_client
      end

      trace_method :get_snapshot, span_attribute_extractor: -> (_instance, *_args, **kwargs) do
        {
          "gh.repo.id" => kwargs[:repository_id],
        }
      end
      # e.g. get_snapshot(repository_id: 1, commit_id: "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d",
      #  tree: [{path: "package.json", blob_id: "7c211433f02071597741e6ff5a8ea34789abbf43"}])
      def get_snapshot(repository_id:, commit_id:, tree:)
        assembler = SnapshotRequests::SnapshotAssembler.new(@blob_operations_provider)
        request = {
          sha: commit_id,
          repository: { id: repository_id },
          tree: tree
        }
        return assembler.assemble_snapshot(request)
      rescue StandardError => exception
        log_then_raise(
          exception,
          "Error fetching snapshot",
          "gh.dependency_graph.blob_operations.provider" => @blob_operations_provider.name,
          "gh.repo.id" => repository_id,
          "gh.commit.sha" => commit_id
        )
      end

      trace_method :compare_snapshots
      def compare_snapshots(base_snapshot, target_snapshot, decompose_updates: false)
        Snapshots::Diff.new(base_snapshot, target_snapshot, decompose_updates: decompose_updates)
      rescue StandardError => exception
        log_then_raise(
          exception,
          "Error calculating snapshot diff",
          "gh.repo.id" => base_snapshot&.github_repository_id,
          "gh.dependency_graph.snapshot.base_sha" => base_snapshot&.metadata&.sha,
          "gh.dependency_graph.snapshot.target_sha" => target_snapshot&.metadata&.sha
        )
      end

      trace_method :get_manifests_page
      def get_manifests_page(twirp_diff, files:, page_number: 1, per_page: MAX_MANIFESTS_PER_PAGE)
        page = {
                  base: [],
                  target: [],
                  page: page_number,
                  per_page: per_page,
                  first: 1,
                  last: nil,
                  unique_files_count: 0,
              }

        base_files = files.base || []
        target_files = files.target || []

        twirp_files = []
        if twirp_diff
          twirp_files = twirp_diff.data.dependency_changes.map(&:manifest).uniq
        end
        combined_files = base_files + target_files
        all_files = combined_files.map(&:path) + twirp_files
        filenames = all_files.uniq.sort
        page[:unique_files_count] = filenames.count
        return page if all_files.empty?

        pages = filenames.each_slice(per_page).to_a
        page[:last] = pages.length

        return page if page_number < 1 || page_number > page[:last]

        page_index = page_number - 1
        page_filenames = pages[page_index]

        page[:base] = base_files.select { |m| page_filenames.include?(m.path) }
        page[:target] = target_files.select { |m| page_filenames.include?(m.path) }
        return page
      end

      def get_twirp_diff(include_dependency_snapshots, repository_id, base_sha, target_sha)
        warnings = []
        return [warnings, nil] unless include_dependency_snapshots
        twirp_diff = @snapshots_client.get_snapshot_diff(repository_id, base_sha, target_sha)
        if twirp_diff.error&.code == :not_found
          # the error may contain additional metadata that specifies that the
          # repo doesn't have any canonical snapshots. In that case, no warning
          # is necessary.
          if twirp_diff.error&.meta.with_indifferent_access[:has_manifests] == "false"
            return [warnings, nil]
          end
          warnings.push "No snapshots were found for the head SHA #{target_sha}."
          return [warnings, nil]
        elsif twirp_diff.error
          exception = StandardError.new("Error code #{twirp_diff.error.code} from DS-API: #{twirp_diff.error.msg[0..100]}")
          log_then_raise(exception, "Error from DS-API")
        end
        if twirp_diff
          twirp_diff.data.dependency_changes.each do |change|
            change.manifest = DependencyGraph::ObjectModel::AbstractManifest.normalize_manifest_path(change.manifest)
          end
        end
        [warnings, twirp_diff]
      end

      def get_snapshots_diff(req, env)
        trace(**get_tracing_payload_from_request(req)) do
          tracing_log = {}
          begin
            validate_base_params(req)

            snapshot_warnings, twirp_diff = get_twirp_diff(req.include_dependency_snapshots, req.repository_id, req.base_sha, req.target_sha)
            paginated_request = req.page_metadata || nil

            # page initially only holds data relevant to dg-api dependencies.
            # it will be updated later with data from ds-api if requested.
            page = if paginated_request
                     per_page = valid_page_size(paginated_request.per_page)
                     get_manifests_page(twirp_diff, files: req.limit_to_files, page_number: paginated_request.page, per_page: per_page)
                  else
                    nil
                  end
          rescue ValidationError => error
            return error.twirp_error.values[0]
          end

          begin
            trees = if page
                      DependencyGraphAPI::V1::LimitToFiles.new(base: page[:base], target: page[:target])
                    else
                      req.limit_to_files
                    end
            if trees.blank?
              base, target = @blob_operations_provider.get_changed_manifests(repository_id: req.repository_id, base_oid: req.base_sha, target_oid: req.target_sha)
              trees = DependencyGraphAPI::V1::LimitToFiles.new(base: base, target: target)
            end

            base_record = get_snapshot(repository_id: req.repository_id, commit_id: req.base_sha, tree: trees.base)
            target_record = get_snapshot(repository_id: req.repository_id, commit_id: req.target_sha, tree: trees.target)
            decompose_updates = req.decompose_updates
            snapshot_diff = compare_snapshots(base_record, target_record, decompose_updates: decompose_updates)

            if req.include_dependency_snapshots && twirp_diff
              additional_snapshot_warnings, page = enrich_with_ds_api_data(twirp_diff, snapshot_diff, req.repository_id, req.base_sha, req.target_sha, page)
              snapshot_warnings += additional_snapshot_warnings
            end
          rescue StandardError => exception
            log_then_raise(exception, exception.message, **get_tracing_payload_from_request(req))
          end

          DependencyGraph.logger.info("Tracing log after calculated diff",
            "gh.dependency_graph.snapshot.diff.changes_count" => snapshot_diff.changes.count,
            **get_tracing_payload_from_request(req).merge!(tracing_log))

          model = snapshot_diff.to_model

          begin
            Instrument.time_dist("snapshot_diff_handler.load_vulnerabilities") do
              model.load_vulnerabilities(decompose_updates: decompose_updates)
            end
          rescue StandardError => exception
            log_then_raise(exception,
              "Vulnerabilities failed to load for snapshot",
              **get_tracing_payload_from_request(req)
            )
          end

          begin
            Instrument.time_dist("snapshot_diff_handler.load_metadata") do
              model.load_metadata
            end
          rescue StandardError => exception
            log_then_raise(exception,
              "Metadata failed to load for snapshot",
              **get_tracing_payload_from_request(req))
          end

          model.load_page_metadata(page) if page

          model.snapshot_warnings = snapshot_warnings
          model.to_twirp
        end
      end

      def get_tracing_payload_from_request(req)
        {
          "gh.repo.id" => req.repository_id,
          "gh.dependency_graph.snapshot.base_sha" => req.base_sha,
          "gh.dependency_graph.snapshot.target_sha" => req.target_sha
        }
      end

      add_log_context :get_snapshots_diff

      private

      # Adds DS-API snapshots data to the given diff via Twirp. Returns two values:
      # - an array of warnings, which may be empty, and do not need to be examined by the caller.
      # - a page object, which should replace the `page` variable in the `get_snapshots_diff` handler method.
      # The warnings array should be added to the response in the `snapshots_warning` field.
      def enrich_with_ds_api_data(twirp_diff, snapshot_diff, repository_id, base_sha, target_sha, page)
        raise "no snapshots client supplied at initialization" unless @snapshots_client
        warnings = []

        new_page = page
        snapshot_diff.combine_with_twirp_diff(twirp_diff)
        base_snapshots_compared = twirp_diff.data.base_snapshots_compared
        head_snapshots_compared = twirp_diff.data.head_snapshots_compared
        if base_snapshots_compared != head_snapshots_compared
          warnings.push(format_snapshot_warning(base_snapshots_compared, head_snapshots_compared))
        end
        [warnings, new_page]
      end

      def format_snapshot_warning(base_snapshots_compared, head_snapshots_compared)
        unexpected_change_type = base_snapshots_compared > head_snapshots_compared ? "removals" : "additions"
        "The number of snapshots compared for the base SHA (#{base_snapshots_compared})" +
          " and the head SHA (#{head_snapshots_compared}) do not match." +
          " You may see unexpected #{unexpected_change_type} in the diff."
      end

      # DESTRUCTIVELY removes any changes from twirp_response that fall outside of the current page,
      # and returns a new page object with the correct "last" page number.
      def paginate_ds_api_twirp_response(twirp_response, page)
        return page unless page && page[:page] && page[:per_page]
        new_page = page.dup
        per_page = page[:per_page]
        total_static_files = page[:unique_files_count]

        # update the "last" page to account for ds-api data
        twirp_changed_manifests = twirp_response.data.dependency_changes.map(&:manifest).uniq
        new_page[:last] = ((page[:unique_files_count] + twirp_changed_manifests.count) / per_page.to_f).ceil

        static_files_on_this_page = (page[:base] + page[:target]).map(&:path).uniq.count
        remaining_space_on_page = per_page - static_files_on_this_page
        if remaining_space_on_page <= 0
          # no more room for dependencies on this page, so we'll have to empty out the twirp response
          twirp_response.data.dependency_changes.clear
          return new_page
        end

        # from here on out, we know that we're paginating the twirp response
        current_page = page[:page] - 1 # correct for 1-based indexing
        # the initial_offset is _almost_ the starting index, but it will be negative if there are static files on this page.
        initial_offset = (current_page * per_page) - total_static_files
        # correct for the case where the initial_offset is negative, since negative indexes don't make sense.
        start_idx = [0, initial_offset].max
        end_idx = (start_idx + remaining_space_on_page)

        # delete all the dependency changes that don't belong on this page
        manifest_paths = twirp_changed_manifests.sort
        keep_manifests = manifest_paths[start_idx...end_idx]
        twirp_response.data.dependency_changes.keep_if { |change| keep_manifests.include?(change.manifest) }

        return new_page
      end

      def default_blob_operations_provider
        SnapshotRequests::Provider::SpokesProvider.new
      end

      def default_snapshots_client
        DependencyGraphAPI::DependencySnapshotsAPI::SnapshotsClient.new
      end

      def validate_property(obj:, symbol:, field_name: nil)
        unless is_property_present(obj: obj, symbol: symbol)
          raise_missing_argument(field_name.nil? ? symbol.to_s : field_name.to_s)
        end
      end

      def raise_missing_argument(arg_name, msg = "is mandatory")
        error = Twirp::Error.invalid_argument(msg, argument: arg_name)
        raise ValidationError.new(twirp_error: error)
      end

      def log_then_raise(exception, message, **tracing_payload)
        DependencyGraph.logger.warn(message,
          tracing_payload,
          exception
        )
        raise exception
      end

      def validate_base_params(req)
        validate_property(obj: req, symbol: :repository_id)
        validate_property(obj: req, symbol: :base_sha)
        validate_property(obj: req, symbol: :target_sha)
      end

      def valid_page_size(per_page)
        # 0 is valid because param will default to 0 in request if unset
        return MAX_MANIFESTS_PER_PAGE if per_page == 0

        if per_page < 0 || per_page > MAX_MANIFESTS_PER_PAGE
          raise_missing_argument("per_page", "should be >= 1 and <= #{MAX_MANIFESTS_PER_PAGE}")
        end

        per_page
      end
    end
  end
end
