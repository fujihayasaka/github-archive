# typed: true
# frozen_string_literal: true

require "monolith-twirp-elm-data"

module Api::Internal::Twirp::Elm
  module Data
    module V1
      # Handler for the MonolithTwirp::Elm::Data::V1::ExportAssetsAPIService
      class ExportAssetsAPIHandler < Api::Internal::Twirp::Handler
        handles_service MonolithTwirp::Elm::Data::V1::ExportAssetsAPIService
        allow_access_for :client, allowed_clients: %w[elm migrations_vnext]

        CROSS_REPO_ERROR_MESSAGE = "Unable to fetch asset: Asset repository_id does not match provided repository_id. Fetching cross-repo assets is not supported."

        # Public: Implementation of the ExportAsset Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Elm::Data::V1::ExportAssetRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Elm::Data::V1::ExportAssetResponse, or a Twirp::Error.
        sig do
          params(
            req: MonolithTwirp::Elm::Data::V1::ExportAssetRequest,
            env: T::Hash[Symbol, T.untyped]
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def export_asset(req, env)
          repo_id = req.repository_id
          return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id") if req.repository_id.zero?

          repository = if FeatureFlag.vexi.enabled?(:repos_by_id_api_twirp, default: false)
            ::Repositories.domain.by_id(repo_id)
          else
            Repository.find_by(id: repo_id)
          end
          if repository.nil?
            return Twirp::Error.not_found("Repository not found", argument: "repository_id", value: repo_id.to_s, elm_error_code: "REPOSITORY_NOT_FOUND")
          elsif repository.deleted?
            return Twirp::Error.not_found("Repository deleted", argument: "repository_id", value: repo_id.to_s, elm_error_code: "REPOSITORY_DELETED")
          end

          markdown_url = req.markdown_url
          return Twirp::Error.invalid_argument("must be non-empty", argument: "markdown_url") if markdown_url.empty?

          asset, asset_type, error = find_asset_by_url(markdown_url)
          return Twirp::Error.not_found("#{asset_type} not found: #{error}", argument: "markdown_url", value: markdown_url) if error.present?

          # Return error if we couldn't find an asset that matches the markdown URL
          return Twirp::Error.not_found("No asset found for URL #{markdown_url}.", argument: "markdown_url", value: markdown_url) unless asset

          # Return error if we're trying to fetch an asset from another repo.
          # Fetching cross-repo assets is not supported at this time until we
          # can get a source_user_id from ELM from the admin running the migration.
          return Twirp::Error.invalid_argument(CROSS_REPO_ERROR_MESSAGE, argument: "repository_id", value: asset.repository_id.to_s, elm_error_code: "CROSS_REPO_ASSET_DETECTED") if cross_repo_asset?(asset, T.must(repository.id))

          build_export_asset_response(asset)
        end

        private

        sig { params(asset: T.untyped, repository_id: Integer).returns(T::Boolean) }
        def cross_repo_asset?(asset, repository_id)
          asset.repository_id.present? && asset.repository_id != repository_id
        end

        sig { params(markdown_url: String).returns(T::Array[T.untyped]) }
        def find_asset_by_url(markdown_url)
          match = AssetScanner.check_url(markdown_url)
          return [nil, nil, nil] unless match.success?

          matched_asset_type = match.match.asset_type

          case matched_asset_type
          when "UserAsset"
            if asset = UserAsset.where(guid: match.match.asset_guid).first
              [asset, matched_asset_type, nil]
            else
              [nil, matched_asset_type, "No user asset found with GUID #{match.match.asset_guid}."]
            end
          when "RepositoryFile"
            if repository_file = RepositoryFile.where(id: match.match.asset_id).first
              [repository_file, matched_asset_type, nil]
            else
              [nil, matched_asset_type, "No repository file found with id #{match.match.asset_id}."]
            end
          else
            [nil, matched_asset_type, "Unknown asset type: #{matched_asset_type}"]
          end
        end

        sig { params(asset_class: T.untyped).returns(Symbol) }
        def map_type_to_protobuf_enum(asset_class)
          case asset_class
          when UserAsset
            :EXPORT_ASSET_TYPE_USER_ASSET
          when RepositoryFile
            :EXPORT_ASSET_TYPE_REPOSITORY_FILE
          else
            :EXPORT_ASSET_TYPE_INVALID
          end
        end

        sig { params(asset: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def build_export_asset_response(asset)
          {
            export_asset: build_export_asset_hash(asset)
          }
        end

        sig { params(asset: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
        def build_export_asset_hash(asset)
          storage_policy = asset.storage_policy(actor: asset.uploader)

          {
            id: asset.id,
            repository_id: asset.repository_id,
            uploader_id: asset.uploader.id,
            asset_type: map_type_to_protobuf_enum(asset),
            file_name: asset.name,
            content_type: asset.content_type,
            size: asset.size,
            markdown_url: asset.storage_external_url,
            signed_download_url: storage_policy.download_url,
            created_at: { seconds: asset.created_at.to_i, nanos: 0 },
            updated_at: { seconds: asset.updated_at.to_i, nanos: 0 }
          }
        end
      end
    end
  end
end
