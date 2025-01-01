# typed: strict
# frozen_string_literal: true

module Storage::UserAssetTransfer
  class RepositoryToRepositoryTransfer < Transfer
    extend T::Sig

    sig { returns(Repository) }
    attr_reader :from_repository, :to_repository

    sig { params(origin: Repository, target: Repository, actor: T.nilable(User)).void }
    def initialize(origin, target, actor)
      super(target, actor)
      @from_repository = origin
      @to_repository = target
    end

    sig do
      params(
        from: Repository,
        to: Repository,
        actor: T.nilable(User),
        urls: T::Array[String]
      ).returns(T::Array[Translation])
    end
    def self.transfer_by_urls(from, to, actor, urls)
      new(from, to, actor).transfer_by_urls(urls)
    end

    sig { params(assets: ActiveRecord::Relation).returns(Integer) }
    def transfer_assets(assets)
      assets.update_all(repository_id: to_repository.id, upload_container_type: nil, upload_container_id: nil)
    end

    sig { params(user_id: Integer, guid: String, use_new_url: T::Boolean).returns(String) }
    def asset_url_translation(user_id, guid, use_new_url)
      return "#{GitHub.url}/user-attachments/assets/#{guid}" if use_new_url

      "#{to_repository.permalink}/assets/#{user_id}/#{guid}"
    end

    sig { params(original_asset_container: OriginalAssetUploadContainer).returns(T::Boolean) }
    def is_original_container_public?(original_asset_container)
      original_repository = Repository.find_by(id: original_asset_container.upload_container_id)
      return false unless original_repository

      original_repository.public?
    end

    sig { params(asset: UserAsset).returns(T.any(Promise[T::Boolean], Promise[FalseClass])) }
    def asset_visible_to_actor?(asset)
      return Promise.resolve(false) unless asset.upload_container&.is_a?(Repository)
      # Reject transfers for assets that are not in the source repository
      return Promise.resolve(false) unless asset.upload_container.id == from_repository.id

      asset.upload_container.async_writable_by?(actor)
    end
  end
end
