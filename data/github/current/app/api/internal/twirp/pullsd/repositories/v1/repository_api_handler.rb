# typed: true
# frozen_string_literal: true

require "monolith-twirp-pullsd-repositories"

module Api::Internal::Twirp::Pullsd
  module Repositories
    module V1
      # Handler for the MonolithTwirp::Pullsd::Repositories::V1::RepositoryAPIService
      class RepositoryAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["pullsd"]
        handles_service MonolithTwirp::Pullsd::Repositories::V1::RepositoryAPIService

        # Public: Implementation of the ManyById Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Pullsd::Repositories::V1::ManyByIdRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # MonolithTwirp::Pullsd::Repositories::V1::ManyByIdResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Pullsd::Repositories::V1::ManyByIdRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Repositories::V1::ManyByIdResponse, Twirp::Error))
        end
        def many_by_id(req, env)
          repository_ids = req.repository_ids.to_a

          if repository_ids.empty?
            return MonolithTwirp::Pullsd::Repositories::V1::ManyByIdResponse.new
          end

          repos = ::Repositories::Public.load_repositories(repository_ids)

          if repos.empty?
            return Twirp::Error.not_found("no repositories found for the given IDs")
          end

          repository_protos = repos.map(&method(:serialize_repository))

          MonolithTwirp::Pullsd::Repositories::V1::ManyByIdResponse.new(
            repositories: repository_protos
          )
        end

        sig do
          params(
            req: MonolithTwirp::Pullsd::Repositories::V1::GetByNwoRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(MonolithTwirp::Pullsd::Repositories::V1::GetByNwoResponse, Twirp::Error))
        end
        def get_by_nwo(req, env)
          owner = User.find_by(login: req.owner_login)
          if owner.nil?
            return Twirp::Error.not_found("no user found with login #{req.owner_login}")
          end

          repository = ::Repositories.domain.by_owner_and_repo_names(req.owner_login, req.name)

          if repository.nil?
            redirected_repository = RepositoryRedirect.find_redirected_repository("#{req.owner_login}/#{req.name}")

            if redirected_repository.present?
              return Twirp::Error.invalid_argument(
                "repository moved permanently to #{redirected_repository.name_with_owner}",
                { "location" => "repositories/#{redirected_repository.id}" }
              )
            else
              return Twirp::Error.not_found("no repository found with name #{req.name} for owner #{req.owner_login}")
            end
          end

          repository = T.cast(repository, ::Repository)

          MonolithTwirp::Pullsd::Repositories::V1::GetByNwoResponse.new(
            repository: serialize_repository(repository),
          )
        end

        sig { params(repo: Repository).returns(MonolithTwirp::Pullsd::Repositories::V1::Repository) }
        def serialize_repository(repo)
          repo_hash = Api::Serializer.serialize(:repository_hash, repo, { use_public_api_url: true })

          MonolithTwirp::Pullsd::Repositories::V1::Repository.new(
            # Core identification and status
            id: repo.id,
            name: repo.name,
            owner_login: repo.owner_login,
            owner_id: repo.owner_id,
            is_private: repo_hash&.dig(:private),
            is_fork: repo_hash&.dig(:fork),
            is_archived: repo_hash&.dig(:archived),
            is_disabled: repo_hash&.dig(:disabled),
            node_id: repo_hash&.dig(:node_id),

            # Basic repository information
            description: repo_hash&.dig(:description),
            has_description: !repo_hash&.dig(:description).nil?,
            homepage: repo_hash&.dig(:homepage),
            has_homepage: !repo_hash&.dig(:homepage).nil?,
            language: repo_hash&.dig(:language),
            has_language: !repo_hash&.dig(:language).nil?,
            visibility: repo_hash&.dig(:visibility),
            is_template: repo_hash&.dig(:is_template),
            topics: repo_hash&.dig(:topics),
            user_hidden: repo.user_hidden?,

            # Repository statistics and counts
            forks_count: repo_hash&.dig(:forks_count),
            stargazers_count: repo_hash&.dig(:stargazers_count),
            open_issues_count: repo_hash&.dig(:open_issues_count),
            size: repo_hash&.dig(:size),

            # Branch information
            default_branch: repo_hash&.dig(:default_branch),
            master_branch: repo_hash&.dig(:master_branch),

            # Feature enablement flags
            has_issues: repo_hash&.dig(:has_issues),
            has_projects: repo_hash&.dig(:has_projects),
            has_wiki: repo_hash&.dig(:has_wiki),
            has_pages: repo_hash&.dig(:has_pages),
            has_downloads: repo_hash&.dig(:has_downloads),
            has_discussions: repo_hash&.dig(:has_discussions),

            # Timestamps (protobuf timestamps)
            pushed_at: repo.pushed_at&.then { |t| Google::Protobuf::Timestamp.new(seconds: t.to_i, nanos: t.nsec) },
            created_at: repo.created_at&.then { |t| Google::Protobuf::Timestamp.new(seconds: t.to_i, nanos: t.nsec) },
            updated_at: repo.updated_at&.then { |t| Google::Protobuf::Timestamp.new(seconds: t.to_i, nanos: t.nsec) },

            # Merge and collaboration settings
            allow_rebase_merge: repo_hash&.dig(:allow_rebase_merge),
            allow_squash_merge: repo_hash&.dig(:allow_squash_merge),
            allow_merge_commit: repo_hash&.dig(:allow_merge_commit),
            allow_auto_merge: repo_hash&.dig(:allow_auto_merge),
            allow_forking: repo_hash&.dig(:allow_forking),
            allow_update_branch: repo_hash&.dig(:allow_update_branch),
            delete_branch_on_merge: repo_hash&.dig(:delete_branch_on_merge),
            is_web_commit_signoff_required: repo_hash&.dig(:web_commit_signoff_required),

            # Merge commit configuration
            use_squash_pr_title_as_default: repo_hash&.dig(:use_squash_pr_title_as_default),
            squash_merge_commit_title: repo_hash&.dig(:squash_merge_commit_title),
            squash_merge_commit_message: repo_hash&.dig(:squash_merge_commit_message),
            merge_commit_title: repo_hash&.dig(:merge_commit_title),
            merge_commit_message: repo_hash&.dig(:merge_commit_message),

            # Special access and tokens
            # Attempt to populate a temp clone token if the repo supports it; this
            # typically requires a user context, which Twirp clients don't provide
            # here, so fall back to an empty string.
            temp_clone_token: (repo.respond_to?(:temp_clone_token) ? repo.temp_clone_token(nil) : ""),
            anonymous_access_enabled: repo_hash&.dig(:anonymous_access_enabled),

            # License information
            license: repo_hash&.dig(:license)
          )
        end
      end
    end
  end
end
