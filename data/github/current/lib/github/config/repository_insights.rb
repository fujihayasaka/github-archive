# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module RepositoryInsights
      def repos_insights_url
        if FeatureFlag.vexi.enabled?(:repos_insights_use_glb_outside_iad, default: false)
          glb_url = GitHub.environment.fetch("REPOS_INSIGHTS_GLB_URL", "http://localhost:28080/twirp")
          # Intentionally degrade to GLB if the mesh URL is missing; in production,
          # GLB is a more useful fallback than the local development default.
          mesh_url = GitHub.environment.fetch("REPOS_INSIGHTS_MESH_URL", glb_url)

          # Because the Repos-Insights service is only deployed in IAD, we cannot use the mesh URL outside IAD.
          # So we need to fall back to the GLB URL in that case.
          return mesh_url if GitHub.environment.fetch("SERVICE_MESH_ENABLED", "false") == "true" && GitHub.server_region == "iad"
          glb_url
        else
          if GitHub.environment.fetch("SERVICE_MESH_ENABLED", "false") == "true"
            GitHub.environment.fetch("REPOS_INSIGHTS_MESH_URL", "http://localhost:28080/twirp")
          else
            GitHub.environment.fetch("REPOS_INSIGHTS_GLB_URL", "http://localhost:28080/twirp")
          end
        end
      end

      def rules_insights_url
        if GitHub.environment.fetch("SERVICE_MESH_ENABLED", "false") == "true"
          GitHub.environment.fetch("RULES_INSIGHTS_MESH_URL", "http://localhost:28080/twirp")
        else
          GitHub.environment.fetch("RULES_INSIGHTS_GLB_URL", "http://localhost:28080/twirp")
        end
      end
    end
  end

  extend Config::RepositoryInsights
end
