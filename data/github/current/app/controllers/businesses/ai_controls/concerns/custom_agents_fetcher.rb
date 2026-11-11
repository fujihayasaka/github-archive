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

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def fetch_custom_agents_data
          with_source_repo_tree("custom agents") do |ctx|
            # Custom agents are in /agents/*.md where * is the snake_case name
            begin
              _, entries, truncated = ctx.repo.tree_entries(ctx.oid, "agents", recursive: false)

              if truncated
                GitHub.logger.warn(
                  "Custom agents tree listing was truncated; some agents may be omitted",
                  "gh.repo.id": ctx.repo.id
                )
              end

              entries.filter_map do |entry|
                next if entry.directory?
                next unless entry.name.end_with?(".md")

                agent_name = entry.name.gsub(/\.md\z/, "").titleize
                agent_file_path = "agents/#{entry.name}"

                {
                  "name" => agent_name,
                  "repo_owner" => ctx.owner,
                  "repo_name" => ctx.name,
                  "url" => blob_view_url(agent_file_path, "HEAD", ctx.repo)
                }
              end
            rescue GitRPC::InvalidObject, GitRPC::NoSuchPath => e
              GitHub.logger.info(
                "Custom agents directory not found or inaccessible",
                "gh.repo.id": ctx.repo.id,
                "error.message": e.message,
                "error.class": e.class.name
              )
              []
            end
          end
        end
      end
    end
  end
end
