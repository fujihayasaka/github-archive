# typed: strict
# frozen_string_literal: true

module Storage::UserAssetTransfer
  class DraftToRepositoryTransferRollback < DraftToRepositoryTransfer
    extend T::Sig

    sig do
      params(
        memex_project: MemexProject,
        actor: T.nilable(User),
        body: T.nilable(String)
      ).void
    end
    def self.rollback_to(memex_project, actor, body)
      new(memex_project, actor).rollback(body)
    end

    sig { params(assets: ActiveRecord::Relation).returns(Integer) }
    def transfer_assets(assets)
      assets.update_all(repository_id: nil, upload_container_type: memex_project.class.name, upload_container_id: memex_project.id)
    end

    sig { returns(T::Boolean) }
    def is_target_public?
      memex_project.public?
    end

    sig { params(user_id: Integer, guid: String, use_new_url: T::Boolean).returns(String) }
    def asset_url_translation(user_id, guid, use_new_url)
      # We don't want to translate urls
      ""
    end

    sig { returns(MemexProject) }
    def memex_project
      T.cast(target, MemexProject)
    end

    sig { params(body: T.nilable(String)).void }
    def rollback(body)
      urls = DraftToRepositoryTransferRollback.extract_urls_from_text(body)
      return if urls.empty?

      transfer_by_urls(urls)
    end

    sig { params(original_asset_container: OriginalAssetUploadContainer).returns(T::Boolean) }
    def is_original_container_public?(original_asset_container)
      repo = Repository.find_by(id: original_asset_container.repository_id)
      return false unless repo

      repo.public?
    end

    sig { params(asset: UserAsset).returns(T.any(Promise[T::Boolean], Promise[FalseClass])) }
    def asset_visible_to_actor?(asset)
      repo = asset.repository
      return Promise.resolve(false) unless repo

      repo.async_readable_by?(actor)
    end
  end
end
