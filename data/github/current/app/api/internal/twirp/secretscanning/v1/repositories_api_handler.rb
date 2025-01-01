# typed: strict
# frozen_string_literal: true

require "secret_scanning_proto"

class Api::Internal::Twirp
  module Secretscanning
    module V1
      class RepositoriesAPIHandler < SecretScanningAPIHandler
        include SecretScanning::Features::FeatureFlagHelper
        handles_service(GitHub::Proto::SecretScanning::Repositories::V1::RepositoryAPIService)

        allow_access_for :client

        BATCH_SIZE = 100

        resolve_tenant_context only: %i[
          get_repository
        ] do |req, _env|
          ::Repositories::Public.resolve_tenant(id: req.repo_id)
        rescue ActiveRecord::RecordNotFound => err
          Twirp::Error.not_found(err.message)
        end

        # list_repositories is only used for partner notifications on public repos, which is not relevant on Proxima
        exempt_from_tenant_context_requirement(only: %i[list_repositories])

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Repositories::V1::GetRepositoryRequest,
            env: T::Hash[String, T.untyped]
          )
          .returns(
            T.any(
              GitHub::Proto::SecretScanning::Repositories::V1::GetRepositoryResponse,
              Twirp::Error
            )
          )
        end
        def get_repository(req, env)
          unless req.repository.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "repository")
          end

          unless req.repository == :repo_id
            return Twirp::Error.invalid_argument("the repository is not a valid input", argument: "repository")
          end

          repo = T.cast(::Repositories.domain.by_id(req.repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast

          unless repo.present?
            return Twirp::Error.not_found("failed to fetch repository", argument: "repo_id")
          end

          GitHub::Proto::SecretScanning::Repositories::V1::GetRepositoryResponse.new({ repositories: repo_to_response(repo) })
        end

        sig do
          params(
            req: GitHub::Proto::SecretScanning::Repositories::V1::ListRepositoriesRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              GitHub::Proto::SecretScanning::Repositories::V1::ListRepositoriesResponse,
              Twirp::Error
            )
          )
        end
        def list_repositories(req, env)
          repos = nil

          if req.organization.present?
            org = Organization.find_by(id: req.org_id)
            unless org.present?
              return Twirp::Error.not_found("the organization does not exist")
            end
            repos = Repository.where(owner_id: req.org_id)
          elsif req.ids_selector.present?
            repos = Repository.where(id: T.must(req.ids_selector).ids.to_a)
          elsif req.org_selector.present?
            org = Organization.find_by(id: T.must(req.org_selector).org_id)
            unless org.present?
              return Twirp::Error.not_found("the organization does not exist")
            end
            repos = Repository.where(owner_id: T.must(req.org_selector).org_id)
          elsif req.user_selector.present?
            user = User.find_by(id: T.must(req.user_selector).user_id)
            unless user.present?
              return Twirp::Error.not_found("the user does not exist")
            end
            repos = Repository.where(owner_id: T.must(req.user_selector).user_id)
          else
            return Twirp::Error.invalid_argument("invalid selector",
              argument: "selector")
          end

          repositories = []
          next_cursor = nil

          last_processed_repo_id = 0
          if req.cursor.present? && !(unpacked = req.cursor.unpack("Q")).empty?
            T.must_because(unpacked[0]) { "unpacked cursor last id cannot be nil" }
            last_processed_repo_id = unpacked[0]
          end

          derived_table_sql = repos.select(:id)
            .where(Repository.arel_table[:id].gt(last_processed_repo_id))
            .order(:id)
            .limit(BATCH_SIZE)
            .to_sql

          repo_batch = Repository.optimizer_hints("JOIN_FIXED_ORDER()")
          .select("r.*")
          .from("(#{derived_table_sql}) as dt")
          .joins("inner join repositories r on r.id = dt.id")
          .order(:id)

          if repo_batch.length != 0
            next_cursor = [T.must(repo_batch.last).id].pack("Q")
            repo_batch.map do |repo|
              next unless repo.owner.present?

              repositories.push(repo_to_response(repo))
            end
          end

          GitHub::Proto::SecretScanning::Repositories::V1::ListRepositoriesResponse.new({ repositories: repositories, next_cursor: next_cursor })
        end

        private

        sig { params(repo: ::Repository).returns(Symbol) }
        def get_repo_visibility(repo)
          return :PUBLIC if repo.public?
          return :PRIVATE if repo.private?
          return :INTERNAL if repo.internal?
          :VISIBILITY_UNKNOWN
        end

        sig { params(owner: T.nilable(::User)).returns(Symbol) }
        def get_user_type(owner)
          return :BOT if owner&.bot?
          return :USER if owner&.user?
          return :ORGANIZATION if owner&.organization?
          :UNKNOWN
        end

        sig { params(repo: ::Repository).returns(GitHub::Proto::SecretScanning::Repositories::V1::Capabilities) }
        def get_capabilities(repo)
          repo_capabilities = SecretScanning::Features::Repo::Capabilities.new(repo)

          if SecretScanning::Features::Repo::WikiScanning.new(repo).enabled?
            return GitHub::Proto::SecretScanning::Repositories::V1::Capabilities.new(
              scannable: repo_capabilities.scannable?,
              results_visible: repo_capabilities.results_visible?,
              ghas_secret_scanning: repo_capabilities.ghas_secret_scanning?,
              validity_checks: repo_capabilities.validity_checks?,
              lower_confidence_patterns: repo_capabilities.lower_confidence_patterns?,
              generic_secrets: repo_capabilities.generic_secrets?,
              wiki_scanning: repo_capabilities.wiki_scanning?,
              push_protection: repo_capabilities.push_protection?,
            )
          end

          GitHub::Proto::SecretScanning::Repositories::V1::Capabilities.new(
            scannable: repo_capabilities.scannable?,
            results_visible: repo_capabilities.results_visible?,
            ghas_secret_scanning: repo_capabilities.ghas_secret_scanning?,
            validity_checks: repo_capabilities.validity_checks?,
            lower_confidence_patterns: repo_capabilities.lower_confidence_patterns?,
            generic_secrets: repo_capabilities.generic_secrets?,
            push_protection: repo_capabilities.push_protection?,
          )
        end

        sig { params(repo: ::Repository).returns(GitHub::Proto::SecretScanning::Repositories::V1::Repository) }
        def repo_to_response(repo)
          business = repo.owner&.business
          business ||= Business.enterprise_managed_business_for(resource: repo)
          business ||= GitHub.global_business if GitHub.single_business_environment?

          GitHub::Proto::SecretScanning::Repositories::V1::Repository.new(
            id: repo.id,
            global_relay_id: repo.global_relay_id,
            name: repo.name,
            parent_id: repo.parent_id,
            network_id: repo.network_id,
            default_branch: repo.default_branch.valid_encoding? ? repo.default_branch : nil,
            default_branch_bytes: repo.default_branch.b,
            created_at: Google::Protobuf::Timestamp.new(seconds: repo.created_at.to_i),
            pushed_at: Google::Protobuf::Timestamp.new(seconds: repo.pushed_at.to_i),
            updated_at: Google::Protobuf::Timestamp.new(seconds: repo.updated_at.to_i),
            owner: GitHub::Proto::SecretScanning::Repositories::V1::User.new(
              id: repo.owner&.id,
              login: feature_flag_enabled_in_hierarchy?(repo, FeatureFlags::USE_DISPLAY_LOGIN_TWIRP) ? repo.owner&.display_login : repo.owner&.login,
              global_relay_id: repo.owner&.global_relay_id,
              type: get_user_type(repo.owner),
              business: GitHub::Proto::SecretScanning::Repositories::V1::Business.new(
                id: business&.id,
                slug: business&.slug,
                name: business&.name,
              ),
            ),
            feature_flags: repo.secret_scanning_post_receive_repo_flags,
            visibility: get_repo_visibility(repo),
            capabilities: get_capabilities(repo),
            is_deleted: repo.deleted?,
            is_archived: repo.archived?,
          )
        end
      end
    end
  end
end
