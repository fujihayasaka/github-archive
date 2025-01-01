# typed: strict
# frozen_string_literal: true
module Storage::UserAssetTransfer
  class Copy < TransferOrCopy
    class CopyPair < T::Struct
      const :original, UserAsset
      const :copy, T.nilable(UserAsset)
    end

    class CopyTimeoutError < TransferOrCopyError; end

    sig { returns(T.nilable(String)) }
    def reason
      "generic_copy"
    end

    # Translates a list of asset URLs to a given target URLs, transfers their underlying assets to the said target and
    # updates the S3 ACLs of the transferred assets based on the target's visibility.
    sig { params(urls: T::Array[String]).returns(UrlTranslations) }
    def copy_by_urls(urls = [])
      filtered_urls = filter_urls(urls)
      return [] if filtered_urls.empty?

      guids = []

      filtered_urls.each do |data|
        guids << data.guid
      end

      assets = UserAsset.where(guid: guids)
      return [] if assets.empty?

      visible_assets = filter_visibile_assets(assets)
      copy_pairs = copy_assets(visible_assets)

      @url_translations = copy_pairs.map do |copy_pair|
        original_url = copy_pair.original.storage_policy.asset_hash[:href]
        copy_url = copy_pair.copy&.storage_policy&.asset_hash&.try(:[], :href) || error_replacement
        Translation.new(original: original_url, translation: copy_url)
      end
    end

    sig { params(assets: T::Array[UserAsset]).returns(T::Array[CopyPair]) }
    def copy_assets(assets)
      GitHub.dogstats.histogram("storage.user_asset_transfer.copy_asset.size_of_bulk", assets.size, tags: ["target:#{target.class.name}", "reason:#{self.reason}"])
      number_of_success = 0
      copy_pairs = T.let([], T::Array[CopyPair])
      GitHub.dogstats.distribution_time("storage.user_asset_transfer.copy_asset.total.duration", tags: ["target:#{target.class.name}", "reason:#{self.reason}"]) do
        begin
          GitHub::Timer.timeout(5, CopyTimeoutError) do
            assets.each do |asset|
              begin
                GitHub.dogstats.distribution_time("storage.user_asset_transfer.copy_asset.single.duration", tags: ["target:#{target.class.name}", "reason:#{self.reason}"]) do
                  copy_pairs << CopyPair.new(original: asset, copy: asset.create_s3_copy(target.class.name, target.id))
                end
                number_of_success += 1
              rescue CopyTimeoutError => e
                raise e # TimeoutError is handled in the outer rescue block
              rescue StandardError => e
                GitHub.logger.error("Failed to copy asset", e)
                copy_pairs << CopyPair.new(original: asset, copy: nil)
              end
            end
          end
        rescue CopyTimeoutError => e
          GitHub.logger.error("Timeout during copying asset", e)
          T.must(assets[number_of_success..]).each do |asset|
            copy_pairs << CopyPair.new(original: asset, copy: nil)
          end
        end
      end
      GitHub.dogstats.increment("storage.user_asset_transfer.copy_asset.finished", by: number_of_success, tags: ["status:success", "target:#{target.class.name}", "reason:#{self.reason}"])
      GitHub.dogstats.increment("storage.user_asset_transfer.copy_asset.finished", by: assets.size - number_of_success, tags: ["status:failed", "target:#{target.class.name}", "reason:#{self.reason}"])
      copy_pairs
    end

    sig { params(assets: ActiveRecord::Relation).returns(T::Array[UserAsset]) }
    def filter_visibile_assets(assets)
      Promise.all(assets.map  do |asset|
                    asset_visible_to_actor?(asset).then do |visible|
                      asset if visible
                    end
                  end).sync.compact
    end

    sig { returns(String) }
    def error_replacement
      <<-REPLACEMENT

> [!WARNING]
> This asset could not be copied from your saved reply. Please try again later.

      REPLACEMENT
    end
  end
end
