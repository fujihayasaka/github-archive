# typed: strict
# frozen_string_literal: true

module Businesses
  module AiControls
    module Concerns
      module CustomAgentsFetcher
        extend ActiveSupport::Concern
        extend T::Helpers
        include Businesses::AiControls::Concerns::SourceRepoTreeReader

        requires_ancestor { Businesses::BusinessController }

        sig { returns(T::Array[String]) }
        def agent_directories
          ["agents", ".github/agents"]
        end

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def fetch_custom_agents_data
          with_source_repo_tree("custom agents") do |ctx|
            custom_agents = T.let([], T::Array[T::Hash[String, T.untyped]])

            # Custom agents can be in /agents/*.md or /.github/agents/*.md
            agent_directories.each do |agent_dir|
              begin
                _, entries, truncated = ctx.repo.tree_entries(ctx.oid, agent_dir, recursive: false)

                if truncated
                  GitHub.logger.warn(
                    "Custom agents tree listing was truncated; some agents may be omitted",
                    "gh.repo.id": ctx.repo.id,
                    "gh.agent_dir": agent_dir
                  )
                end

                entries.each do |entry|
                  next if entry.directory?
                  next unless entry.name.end_with?(".md")

                  agent_name = entry.name.gsub(/\.md\z/, "").titleize
                  agent_file_path = "#{agent_dir}/#{entry.name}"

                  custom_agents << {
                    "name" => agent_name,
                    "repo_owner" => ctx.owner,
                    "repo_name" => ctx.name,
                    "url" => blob_view_url(agent_file_path, "HEAD", ctx.repo)
                  }
                end
              rescue GitRPC::NoSuchPath
                # Directory does not exist; this is expected for repos that don't use this path
              rescue GitRPC::InvalidObject => e
                GitHub.logger.info(
                  "Custom agents directory not found or inaccessible",
                  "gh.repo.id": ctx.repo.id,
                  "gh.agent_dir": agent_dir,
                  "error.message": e.message,
                  "error.class": e.class.name
                )
              end
            end

            custom_agents
          end
        end
      end
    end
  end
end
