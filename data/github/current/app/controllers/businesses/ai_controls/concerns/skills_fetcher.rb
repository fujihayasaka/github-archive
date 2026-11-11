# typed: strict
# frozen_string_literal: true

module Businesses
  module AiControls
    module Concerns
      module SkillsFetcher
        extend ActiveSupport::Concern
        extend T::Helpers
        include Businesses::AiControls::Concerns::SourceRepoTreeReader

        requires_ancestor { Businesses::BusinessController }

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def fetch_skills_data
          with_source_repo_tree("skills") do |ctx|
            # Skills are in /skills/<skill-name>/SKILL.md where <skill-name> is the directory name.
            # Fetch recursively in a single GitRPC call and filter for SKILL.md entries.
            begin
              _, entries, truncated = ctx.repo.tree_entries(ctx.oid, "skills", recursive: true)

              if truncated
                GitHub.logger.warn(
                  "Skills tree listing was truncated; some skills may be omitted",
                  "gh.repo.id": ctx.repo.id
                )
              end

              entries.filter_map do |entry|
                next if entry.directory?
                next unless entry.name == "SKILL.md"

                # Extract the skill directory name from the path (e.g. "skills/skill_name/SKILL.md" -> "skill_name")
                parts = entry.path.split("/")
                next unless parts.length == 3

                skill_dir_name = parts[1]
                next if skill_dir_name.nil?

                {
                  "name" => skill_dir_name.titleize,
                  "repo_owner" => ctx.owner,
                  "repo_name" => ctx.name,
                  "url" => blob_view_url(entry.path, "HEAD", ctx.repo)
                }
              end
            rescue GitRPC::InvalidObject, GitRPC::NoSuchPath => e
              GitHub.logger.info(
                "Skills directory not found or inaccessible",
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
