# typed: strict
# frozen_string_literal: true

module Businesses
  module AiControls
    module Concerns
      module CustomAgentsFetcher
        extend ActiveSupport::Concern
        extend T::Helpers

        requires_ancestor { Businesses::BusinessController }

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def fetch_custom_agents_data
          source_repo_id = this_business.subagent_definitions_source_repository_id
          repo = source_repo_id.present? ? Repositories::Public.find_active(source_repo_id) : nil

          return [] if repo.nil?

          # Load custom agents directly from the repository
          begin
            nwo = repo.name_with_display_owner
            owner, name = nwo.split("/")

            custom_agents = []

            # Get OID from the default branch
            default_branch_name = repo.default_branch
            return custom_agents if default_branch_name.blank?

            default_branch = repo.heads.find(default_branch_name)
            return custom_agents if default_branch.nil?

            oid = default_branch.target_oid
            return custom_agents unless GitRPC::Util.valid_full_oid?(oid)

            # Custom agents are in /agents/*.md where * is the snake_case name
            begin
              _, entries, _ = repo.tree_entries(oid, "agents", recursive: false)

              entries.each do |entry|
                next if entry.directory?
                next unless entry.name.end_with?(".md")

                # Extract name from filename (remove .md extension and titleize)
                agent_name = entry.name.gsub(/\.md\z/, "").titleize
                agent_file_path = "agents/#{entry.name}"

                custom_agents << {
                  "name" => agent_name,
                  "repo_owner" => owner,
                  "repo_name" => name,
                  "url" => blob_view_url(agent_file_path, "HEAD", repo)
                }
              end
            rescue GitRPC::InvalidObject, GitRPC::NoSuchPath => e
              GitHub.logger.info(
                "Custom agents directory not found or inaccessible",
                "gh.repo.id": repo.id,
                "error.message": e.message,
                "error.class": e.class.name
              )
              return []
            end

            custom_agents
          rescue StandardError => e
            GitHub.logger.warn(
              "Error fetching custom agents data",
              "gh.repo.id": repo.id,
              "error.message": e.message,
              "error.class": e.class.name,
            )
            []
          end
        end
      end
    end
  end
end
