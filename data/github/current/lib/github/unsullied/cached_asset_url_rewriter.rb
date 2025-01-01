# typed: strict
# frozen_string_literal: true

# This file is owned by the @github/object-storage team
module GitHub::Unsullied
  class CachedAssetUrlRewriter
    class AssetData < T::Struct
      const :user_id, String, default: ""
      const :guid, String, default: ""
    end

    sig { params(cached: Page::DataHtml).void }
    def initialize(cached)
      @cached = cached
    end

    sig { returns(Regexp) }
    def regex_pattern
      raise NotImplementedError
    end

    sig { params(asset: UserAsset).returns(String) }
    def rewrite_url_asset(asset)
      raise NotImplementedError
    end

    sig { params(host: String).returns(T::Boolean) }
    def is_host_valid?(host)
      true
    end

    sig { returns(Page::DataHtml) }
    def rewrite
      urls = Storage::UserAssetTransfer::TransferOrCopy.extract_urls_from_text(@cached.html).uniq
      return @cached unless urls.any?

      urls.each do |url|
        uri = parse_url(url)
        next unless uri
        next unless uri.host

        next unless is_host_valid?(uri.host)
        next unless uri.path.match?(regex_pattern)

        asset_data = extract_asset_data_from_path(uri.path)
        asset = UserAsset.find_by(user_id: asset_data.user_id, guid: asset_data.guid)
        next unless asset

        new_url = rewrite_url_asset(asset)
        @cached.html.gsub!(url, new_url)
      end

      @cached.html = GitHub::HTML::Result.to_html({ output: @cached.html, html_safe: true })
      @cached
    end

    private

    sig { params(url: String).returns(T.nilable(Addressable::URI)) }
    def parse_url(url)
      begin
        Addressable::URI.parse(url)
      rescue Addressable::URI::InvalidURIError
        nil
      end
    end

    sig { params(path: String).returns(AssetData) }
    def extract_asset_data_from_path(path)
      match = path.match(regex_pattern)
      return AssetData.new unless match

      uid = match[:uid] || ""
      guid = match[:guid] || ""
      AssetData.new(user_id: uid, guid: guid)
    end
  end
end
