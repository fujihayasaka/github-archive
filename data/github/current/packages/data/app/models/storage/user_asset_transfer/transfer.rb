# typed: strict
# frozen_string_literal: true

module Storage::UserAssetTransfer
  class Transfer < TransferOrCopy
    class TransferError < TransferOrCopyError; end

    # Translates a list of asset URLs to a given target URLs, transfers their underlying assets to the said target and
    # updates the S3 ACLs of the transferred assets based on the target's visibility.
    sig { params(urls: T::Array[String]).returns(UrlTranslations) }
    def transfer_by_urls(urls = [])
      filtered_urls = filter_urls(urls)
      return [] if filtered_urls.empty?

      user_ids = []
      guids = []

      filtered_urls.each do |data|
        # Translated URL format is based on the URL format of the original asset - if it uses an
        # old-style URL, we translate to an old-style URL
        translation = asset_url_translation(data.uid, data.guid, data.uses_new_url)
        @url_translations << Translation.new(original: data.url, translation: translation) if !translation.empty?

        user_ids << data.uid
        guids << data.guid
      end

      assets = UserAsset.where(guid: guids)
      return [] if assets.empty?

      raise TransferError.new("Actor is not authorized to transfer some of the assets") unless assets_visible_to_actor?(assets)

      original_assets_upload_containers_data(assets)

      updated_count = transfer_assets(assets)
      raise TransferError.new("Could not transfer assets") if updated_count.zero?

      handle_s3_objects(assets) if should_handle_s3_objects?

      @url_translations
    end

    sig { params(assets: ActiveRecord::Relation).returns(Integer) }
    def transfer_assets(assets)
      assets.update_all(repository_id: nil, upload_container_type: target.class.name, upload_container_id: target.id)
    end

    sig { returns(T::Boolean) }
    def is_target_public?
      raise NotImplementedError
    end

    sig { params(user_id: Integer, guid: String, use_new_url: T::Boolean).returns(String) }
    def asset_url_translation(user_id, guid, use_new_url)
      ""
    end

    sig { params(original_asset_container: OriginalAssetUploadContainer).returns(T::Boolean) }
    def is_original_container_public?(original_asset_container)
      raise NotImplementedError
    end

    private

    sig { params(url: String).returns(T.nilable(Addressable::URI)) }
    def parse_uri(url)
      begin
        Addressable::URI.parse(url)
      rescue Addressable::URI::InvalidURIError => error
        nil
      end
    end

    sig { params(assets: ActiveRecord::Relation).void }
    def rollback_assets(assets)
      @url_translations = []

      assets.each do |asset|
        original = @original_asset_upload_container[asset.id]
        next unless original

        asset.update(
          repository_id: original.repository_id,
          upload_container_type: original.upload_container_type,
          upload_container_id: original.upload_container_id
        )
      end
    end

    sig { params(asset_id: Integer).returns(T::Boolean) }
    def is_visibility_changing?(asset_id)
      original_container = @original_asset_upload_container[asset_id]
      return false unless original_container

      is_original_container_public?(original_container) != is_target_public?
    end
  end
end
