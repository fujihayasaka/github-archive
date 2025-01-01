# typed: strict
# frozen_string_literal: true

module Storage::UserAssetTransfer
  class GistAssetBackfiller < TransferOrCopy
    sig do
      params(
        gist: Gist,
        actor: T.nilable(User),
        urls: T::Array[String]
      ).void
    end
    def self.backfill_upload_container_ids(gist, actor, urls)
      new(gist, actor).backfill_upload_container_ids(urls)
    end

    sig { params(urls: T::Array[String]).void }
    def backfill_upload_container_ids(urls = [])
      return if actor.nil?

      filtered_urls = filter_urls(urls)
      return if filtered_urls.empty?

      guids = filtered_urls.map(&:guid)
      assets = UserAsset.where(user_id: actor&.id, guid: guids, upload_container_type: Gist.name, upload_container_id: nil)
      return if assets.empty?

      backfill_upload_container_id(assets)
    end

    sig { params(assets: ActiveRecord::Relation).returns(Integer) }
    def backfill_upload_container_id(assets)
      assets.update_all(upload_container_id: gist.id)
    end

    sig { returns(Gist) }
    def gist
      T.cast(target, Gist)
    end
  end
end
