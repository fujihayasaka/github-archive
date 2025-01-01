# typed: true
# frozen_string_literal: true
module Api::Internal::Twirp::Insights
  module Core
    module V1
      class GetRepositoryRecord
        include Api::Internal::Twirp::Insights::Core::V1::ActorsDependency

        attr_reader :req, :env

        def self.call(req, env)
          ActiveRecord::Base.connected_to(role: :reading) do
            new(req, env).call
          end
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          repo_id = req.repo_id
          if repo_id.blank?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id")
          end

          unless repo = Repository.find_by(id: repo_id)
            return Twirp::Error.not_found("repository does not exist", argument: "id")
          end

          {
            name: repo.name,
            owner_id: repo.owner_id,
            parent_id: repo.parent_id,
            sandbox: repo.sandbox,
            updated_at: Google::Protobuf::Timestamp.new(seconds: repo.updated_at.to_i),
            created_at: Google::Protobuf::Timestamp.new(seconds: repo.created_at.to_i),
            is_public: repo.public,
            description: repo.description,
            homepage: repo.homepage,
            source_id: repo.source_id,
            public_push: repo.public_push,
            disk_usage: repo.disk_usage,
            is_locked: repo.locked,
            pushed_at: Google::Protobuf::Timestamp.new(seconds: repo.pushed_at.to_i),
            watcher_count: repo.stargazer_count,
            public_fork_count: repo.public_fork_count,
            primary_language_name_id: repo.primary_language_name_id,
            has_issues: repo.has_issues,
            has_wiki: repo.has_wiki,
            has_downloads: repo.has_downloads,
            organization_id: repo.organization_id,
            disabled_at: Google::Protobuf::Timestamp.new(seconds: repo.disabled_at.to_i),
            disabled_by: repo.disabled_by,
            disabling_reason: repo.disabling_reason,
            health_status: repo.health_status,
            pushed_at_usec: repo.pushed_at_usec,
            active: repo.active,
            reflog_sync_enabled: repo.reflog_sync_enabled,
            made_public_at: Google::Protobuf::Timestamp.new(seconds: repo.made_public_at.to_i),
            user_hidden: repo.user_hidden,
            is_maintained: repo.maintained,
            has_template: repo.template,
            owner_login: repo.owner_login,
            is_world_writable_wiki: repo.world_writable_wiki,
            refset_updated_at: Google::Protobuf::Timestamp.new(seconds: repo.refset_updated_at.to_i),
            disabling_detail: repo.disabling_detail
          }
        end
      end
    end
  end
end
