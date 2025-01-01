# typed: strict
# frozen_string_literal: true

class Storage::UserAssetTransfer::TransferOrCopy
  class FielteredUrl < T::Struct
    const :url, String, default: ""
    const :uid, Integer, default: 0
    const :guid, String, default: ""
    const :uses_new_url, T::Boolean, default: false
  end

  class Translation < T::Struct
    const :original, String, default: ""
    const :translation, String, default: ""
  end

  class OriginalAssetUploadContainer < T::Struct
    const :user_asset_id, Integer
    const :repository_id, T.nilable(Integer)
    const :upload_container_type, T.nilable(String)
    const :upload_container_id, T.nilable(Integer)
  end

  class TransferOrCopyError < StandardError; end

  OriginalAssetUploadContainerMap = T.type_alias { T::Hash[Integer, OriginalAssetUploadContainer] }
  UrlTranslations = T.type_alias { T::Array[Translation] }

  sig { params(text: T.nilable(String)).returns(T::Array[String]) }
  def self.extract_urls_from_text(text)
    return [] unless text
    text = text.scrub("")
    # For some reason, urls wrapped in parentheses are being extracted with the closing parenthesis included.
    # E.g.
    #   URI.extract("\n\n![Image](http://github.localhost/some/path)\n\n", ["https", "http"])
    #   => ["http://github.localhost/some/path)"]
    URI.extract(text, %w[http https]).map { |url| url.delete(")") }.uniq
  end

  sig { returns(T.nilable(User)) }
  attr_reader :actor

  sig { returns(ActiveRecord::Base) }
  attr_reader :target

  sig { returns(OriginalAssetUploadContainerMap) }
  attr_reader :original_asset_upload_container

  sig { returns(UrlTranslations) }
  attr_reader :url_translations

  sig { params(target: ActiveRecord::Base, actor: T.nilable(User)).void }
  def initialize(target, actor)
    @target = target
    @actor = actor
    @original_asset_upload_container = T.let({}, OriginalAssetUploadContainerMap)
    @url_translations = T.let([], UrlTranslations)
  end

  sig { params(path: String).returns(T::Boolean) }
  def extra_matcher_passed?(path)
    true
  end

  sig { params(assets: ActiveRecord::Relation).void }
  def handle_s3_objects(assets); end

  private

  sig {  params(assets: ActiveRecord::Relation).void }
  def original_assets_upload_containers_data(assets)
    assets.each do |asset|
      @original_asset_upload_container[asset.id] = OriginalAssetUploadContainer.new(
        user_asset_id: asset.id,
        repository_id: asset.repository_id,
        upload_container_type: asset.upload_container_type,
        upload_container_id: asset.upload_container_id
      )
    end
  end

  sig { params(urls: T::Array[String]).returns(T::Array[FielteredUrl]) }
  def filter_urls(urls)
    guid_regex = GitHub::Goomba::Async::AssetLoaders::AssetLoader::GUID_REGEX
    asset_loader = GitHub::Goomba::Async::AssetLoaders::AssetLoader.new(nil)

    fieltered_data = []
    unique_urls = urls.uniq

    unique_urls.each do |url|
      uri = parse_uri(url)
      next if uri.nil? || !asset_loader.is_uri_valid?(uri)

      next unless uri.path.match?(guid_regex)

      guid_match = uri.request_uri.match(guid_regex)
      next unless guid_match

      new_url_match = uri.path.match?(/\/user-attachments\/assets\//)

      uid = 0
      unless new_url_match
        uid_match = uri.path.match(/\/assets\/(?<uid>\d+)/)
        next unless uid_match
        uid = uid_match[:uid].to_i
      end

      # All upload containers now use the same URL format, so there's no need
      # to check the extra matcher for new-style URLs
      next unless new_url_match || extra_matcher_passed?(uri.path)

      fieltered_data << FielteredUrl.new(
        url: url,
        uid: uid,
        guid: guid_match.to_s,
        uses_new_url: new_url_match
      )
    end

    fieltered_data
  end

  sig { params(url: String).returns(T.nilable(Addressable::URI)) }
  def parse_uri(url)
    begin
      Addressable::URI.parse(url)
    rescue Addressable::URI::InvalidURIError => error
      nil
    end
  end


  sig { params(asset: UserAsset).returns(T.any(Promise[T::Boolean], Promise[TrueClass])) }
  def asset_visible_to_actor?(asset)
    Promise.resolve(true)
  end

  sig { params(assets: ActiveRecord::Relation).returns(T::Boolean) }
  def assets_visible_to_actor?(assets)
    promises = assets.map { |asset| asset_visible_to_actor?(asset) }
    Promise.all(promises)
      .then { |res| res.compact.uniq }
      .then { |res| res.include?(false) ? false : true }
      .sync
  end


  sig { returns(T::Boolean) }
  def should_handle_s3_objects?
    # In a multi-tenant environment, all assets are intended to be private, and their ACLs are set to private as well.
    # In GitHub Enterprise Server (GHES), we use Alambic instead of S3, so there is no need to update ACLs.
    !GitHub.multi_tenant_enterprise? && !GitHub.storage_cluster_enabled?
  end
end
