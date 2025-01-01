module RepositoryService
  module V1
    class Handler < TracedHandler

      # Given a GitHub repository ID, it returns an array of 0 or more repository IDs
      # that are the source of each package the input repo depends on.
      #
      # See also: https://github.com/github/dependency-graph/issues/409
      def get_direct_dependencies(req, env)
        trace(
          **get_tracing_payload_from_get_request(req)
        ) do
          result = validate_read_params(req)
          return twirp_400(fields: result[:missing_fields]) unless result[:params_present]

          tracing_log = {}
          repository = find_by_github_repo_id(req.repository_id, "repository_id", tracing_log)
          return Twirp::Error.new(:not_found, "Repository not found") unless repository.present?

          pkg_manager_selectors = []
          begin
            pkg_manager_selectors = req.package_managers.map do |pm|
              id = DependencyGraphAPI::V1::PackageManager.resolve(pm)
              Types::PackageManager.coerce(id)
            end
          rescue TypeError => e
            return Twirp::Error.new(:bad_request, "Invalid or unsupported package manager ID in request, got: #{e}")
          end


          dependency_repo_ids = Instrument.time_dist("repository_handler.get_direct_dependencies.query") do
            repository
              .abstract_dependencies
              .packages
              .where({ package_manager: pkg_manager_selectors.presence }.compact)
              .where.not(github_repository_id: nil)
              .distinct
              .pluck(:github_repository_id)
          end

          # limit logging to first N repos in the list here?
          tracing_log[:dependency_repo_ids] = dependency_repo_ids
          DependencyGraph.logger.info(message: "Tracing log after get repository dependencies",
                                      **get_tracing_payload_from_get_request(req).merge!(tracing_log))

          DependencyGraphAPI::V1::GetDirectDependenciesResponse.new(
            repository_ids: dependency_repo_ids,
          )
        end
      end

      add_log_context :get_direct_dependencies

      private

      def get_tracing_payload_from_get_request(req)
        {
          github_repository_id: req.repository_id,
        }
      end

      def validate_read_params(req)
        missing_fields = []
        missing_fields.push(:repository_id) unless is_property_present(obj: req, symbol: :repository_id)

        {
          params_present: missing_fields.empty?,
          missing_fields: missing_fields
        }
      end
    end
  end
end
