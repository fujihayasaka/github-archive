# typed: strict
# frozen_string_literal: true

module Storage::UserAssetTransfer
  class DraftToRepositoryTransfer < Transfer
    extend T::Sig

    sig do
      params(
        repository: Repository,
        actor: T.nilable(User),
        urls: T::Array[String]
      ).returns(T::Array[Translation])
    end
    def self.transfer_by_urls(repository, actor, urls)
      new(repository, actor).transfer_by_urls(urls)
    end

    sig { params(path: String).returns(T::Boolean) }
    def extra_matcher_passed?(path)
      path.match?(/\A\/(users|orgs)\/[^\/]+\/projects\/[^\/]+\/assets\//)
    end

    sig { params(assets: ActiveRecord::Relation).returns(Integer) }
    def transfer_assets(assets)
      assets.update_all(repository_id: repository.id, upload_container_type: nil, upload_container_id: nil)
    end

    sig { returns(T::Boolean) }
    def is_target_public?
      repository.public?
    end

    sig { params(user_id: Integer, guid: String, use_new_url: T::Boolean).returns(String) }
    def asset_url_translation(user_id, guid, use_new_url)
      return "#{GitHub.url}/user-attachments/assets/#{guid}" if use_new_url
      "#{repository.permalink}/assets/#{user_id}/#{guid}"
    end

    sig { returns(Repository) }
    def repository
      T.cast(target, Repository) # rubocop:todo GitHub/AvoidCast
    end

    sig { params(assets: ActiveRecord::Relation).void }
    def handle_s3_objects(assets)
      new_acl = is_target_public? ? "public-read" : "private"

      assets.each do |asset|
        next unless asset.storage_provider == :s3_production_data
        next unless is_visibility_changing?(asset.id)

        begin
          GitHub.s3_production_data_client.put_object_acl(
            acl: new_acl,
            bucket: asset.storage_s3_bucket,
            key: asset.storage_s3_key(nil)
          )
        rescue StandardError => e
          rollback_assets(assets)
          raise TransferError.new("Failed to update ACL for asset #{asset.id} to #{new_acl}: #{e.message}")
        end
      end
    end

    sig { params(original_asset_container: OriginalAssetUploadContainer).returns(T::Boolean) }
    def is_original_container_public?(original_asset_container)
      memex = MemexProject.find_by(id: original_asset_container.upload_container_id)
      return false unless memex

      memex.public?
    end

    sig { params(asset: UserAsset).returns(T.any(Promise[T::Boolean], Promise[FalseClass])) }
    def asset_visible_to_actor?(asset)
      return Promise.resolve(false) unless asset.upload_container&.is_a?(MemexProject)

      asset.upload_container.async_viewer_can_read?(actor)
    end
  end
end
