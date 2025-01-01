# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-imports"

module Api::Internal::Twirp::Octoshift
  module Imports
    module V1
      class ImportAssetAPIHandler < Api::Internal::Twirp::Handler
        include Helpers::ErrorHandler
        include Helpers::ModelDelay

        ASSET_TYPE_MAP = {
          "UserAsset" => :ASSET_TYPE_USER_ASSET,
          "RepositoryFile" => :ASSET_TYPE_REPOSITORY_FILE,
          "ReleaseAsset" => :ASSET_TYPE_RELEASE_ASSET
        }.freeze

        STORAGE_POLICY_TYPE_MAP = {
          "Storage::ClusterPolicy" => :STORAGE_POLICY_TYPE_CLUSTER,
          "Storage::S3Policy" => :STORAGE_POLICY_TYPE_S3,
          "Storage::MemoryAlphaPolicy" => :STORAGE_POLICY_TYPE_MEMORY_ALPHA
        }.freeze

        ASSET_TYPE_CLASS_MAP = {
          ASSET_TYPE_USER_ASSET: UserAsset,
          ASSET_TYPE_REPOSITORY_FILE: RepositoryFile,
          ASSET_TYPE_RELEASE_ASSET: ReleaseAsset
        }.freeze

        allow_access_for :client, allowed_clients: ["octoshift"]
        handles_service MonolithTwirp::Octoshift::Imports::V1::ImportAssetAPIService

        # Public: Implementation of the CreateAssetStoragePolicy Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::CreateAssetStoragePolicyRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::CreateAssetStoragePolicyResponse, or a Twirp::Error.
        def create_asset_storage_policy(req, env)
          # Parameter validations
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end
          if req.name.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "name")
          end
          if req.size.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "size")
          end
          if req.content_type.empty?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "content_type")
          end
          if req.actor_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "actor_id")
          end
          if req.asset_type == :ASSET_TYPE_INVALID
            return Twirp::Error.invalid_argument("must be a valid enum", argument: "asset_type")
          end

          if req.asset_type == :ASSET_TYPE_RELEASE_ASSET
            if req.release_id.zero?
              return Twirp::Error.invalid_argument("must be positive integer", argument: "release_id")
            end

            release = ActiveRecord::Base.connected_to(role: :writing) do
              Releases::Public.load_release(req.release_id)
            end

            unless release
              return Twirp::Error.not_found("Release not found.", argument: "release_id", value: req.release_id.to_s)
            end
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          actor = replica(User).find_by(id: req.actor_id)
          unless actor
            return Twirp::Error.not_found("Actor not found.", argument: "actor_id", value: req.actor_id.to_s)
          end

          # Setup asset metadata for uploadable object
          asset_metadata = {}
          asset_metadata[:name] = req.name
          asset_metadata[:size] = req.size
          asset_metadata[:content_type] = req.content_type
          asset_metadata[:repository_id] = req.repository_id
          asset_metadata[:release_id] = req.release_id if req.asset_type == :ASSET_TYPE_RELEASE_ASSET
          asset_metadata[:label] = req.label.presence if req.asset_type == :ASSET_TYPE_RELEASE_ASSET

          # Determine uploadable class
          uploadable_class = get_uploadable_class(req.asset_type, req.content_type)
          uploadable = uploadable_class.storage_new(actor, nil, asset_metadata)

          # Create uploadable and set base attributes
          ActiveRecord::Base.connected_to(role: :writing) do
            uploadable.size = req.size
            uploadable.storage_blob = ::Storage::Blob.new(size: asset_metadata[:size]) if set_storage_blob?(uploadable)
          end


          # Build and return hash for storage policy
          if GitHub.storage_cluster_enabled?
            # Return error early if model fails to validate. Alambic has full control of the upload process
            # and will handle persisting model and tracking as uploaded so we do not save model here.
            return save_model_error_handler(uploadable) unless uploadable.valid?

            policy_hash_for_cluster_policy(uploadable, actor)
          else
            # Return error early if model fails to validate and save. We need a persisted uploadable
            # in non storage cluster configuration so model gets saved and Octoshift will track model as uploaded.
            ActiveRecord::Base.connected_to(role: :writing) do
              return save_model_error_handler(uploadable) unless uploadable.save
            end

            policy_hash_for_s3_policy(uploadable, actor)
          end
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        # Public: Implementation of the TrackAssetAsUploaded Twirp RPC.
        #
        # req - The Twirp request as a MonolithTwirp::Octoshift::Imports::V1::TrackAssetAsUploadedRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response as a Hash suitable for use in a
        # MonolithTwirp::Octoshift::Imports::V1::TrackAssetAsUploadedResponse, or a Twirp::Error.
        def track_asset_as_uploaded(req, env)
          # Parameter validations
          if req.repository_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "repository_id")
          end
          if req.asset_id.zero?
            return Twirp::Error.invalid_argument("must be positive integer", argument: "asset_id")
          end
          if req.asset_type == :ASSET_TYPE_INVALID || req.asset_type == :ASSET_TYPE_AUTO
            return Twirp::Error.invalid_argument("must be a valid asset type", argument: "asset_type")
          end

          repository = replica(Repository).find_by(id: req.repository_id)
          unless repository && repository.active?
            return Twirp::Error.not_found("Repository not found.", argument: "repository_id", value: req.repository_id.to_s, octoshift_error_code: "REPOSITORY_DELETED")
          end

          # Find uploadable object
          uploadable_class = get_uploadable_class(req.asset_type, nil)

          uploadable = replica(uploadable_class).find_by(id: req.asset_id, repository_id: req.repository_id)

          unless uploadable
            return Twirp::Error.not_found("#{uploadable_class.name} not found.", argument: "asset_id", value: req.asset_id.to_s)
          end

          # Update state to :uploaded
          ActiveRecord::Base.connected_to(role: :writing) do
            uploadable.track_uploaded
          end

          # Return nothing
          {}
        rescue Api::Internal::Twirp::Octoshift::Errors::HighReplicationDelay => error
          replication_delay_error_handler(error.delay, error.role)
        end

        private

        def get_uploadable_class(asset_type, content_type)
          return ASSET_TYPE_CLASS_MAP[asset_type] unless asset_type == :ASSET_TYPE_AUTO

          # For :ASSET_TYPE_AUTO, determine the uploadable class from the content type.
          return UserAsset if ::Storage::Uploadable::CONTENT_TYPES[:media].include?(content_type)
          RepositoryFile
        end

        def set_storage_blob?(uploadable)
          GitHub.storage_cluster_enabled? && uploadable.respond_to?(:storage_blob)
        end

        def policy_hash_for_cluster_policy(uploadable, actor)
          policy = uploadable.storage_policy(actor: actor)
          policy_hash = policy.policy_hash

          headers = policy_hash[:header].map { |k, v| { "key" => k, "value" => v.to_s } }
          form_data = policy_hash[:form].map { |k, v| { "key" => k, "value" => v.to_s } }

          {
            upload_url: policy_hash[:upload_url],
            headers: headers,
            form_data: form_data,
            asset_url: nil, # Alambic will return the asset URL as part of its upload response
            asset_type: ASSET_TYPE_MAP[uploadable.class.name],
            asset_id: nil, # Alambic will return the asset ID as part of its upload response
            storage_policy_type: STORAGE_POLICY_TYPE_MAP[policy.class.name]
          }
        end

        def policy_hash_for_s3_policy(uploadable, actor)
          policy = uploadable.storage_policy(actor: actor)
          policy_hash = policy.policy_hash

          form_data = policy_hash[:form].map { |k, v| { "key" => k, "value" => v.to_s } }

          {
            upload_url: policy_hash[:upload_url],
            headers: [],
            form_data: form_data,
            asset_url: policy_hash[:asset][:href],
            asset_type: ASSET_TYPE_MAP[uploadable.class.name],
            asset_id: uploadable.id,
            storage_policy_type: STORAGE_POLICY_TYPE_MAP[policy.class.name]
          }
        end

        def save_model_error_handler(model)
          error_messages = model.errors.full_messages

          if error_messages.detect { |m| m.include?("Size Yowza") }
            error_messages = error_messages.map { |s| s.gsub(%r{\ASize Yowza.*\Z}, "Size is not included in the list") }
          end

          Twirp::Error.canceled("Could not create #{model.class.name}: #{error_messages.join(", ")}")
        end
      end
    end
  end
end
