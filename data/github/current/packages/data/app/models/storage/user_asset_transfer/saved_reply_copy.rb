# typed: strict
# frozen_string_literal: true

module Storage::UserAssetTransfer
  class SavedReplyCopy < Copy
    sig do
      params(
        target: ActiveRecord::Base,
        actor: T.nilable(User),
        urls: T::Array[String]
      ).returns(T::Array[Translation])
    end
    def self.copy_by_urls(target, actor, urls)
      return [] if urls.empty?
      return [] if target == actor # No need to copy if the target is the actor since it is already the container
      new(target, actor).copy_by_urls(urls)
    end

    sig { params(path: String).returns(T::Boolean) }
    def extra_matcher_passed?(path)
      path.include?("/settings/replies/assets/")
    end

    sig { params(asset: UserAsset).returns(Promise[T::Boolean]) }
    def asset_visible_to_actor?(asset)
      Promise.resolve(asset.upload_container == actor)
    end

    sig { returns(T.nilable(String)) }
    def reason
      "saved_reply"
    end
  end
end
