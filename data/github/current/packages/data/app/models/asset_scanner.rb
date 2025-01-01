# typed: false
# frozen_string_literal: true

class AssetScanner
  # Public: Check to see if the given image URL is a UserAsset.
  # Returns a MatchResult.
  def self.check_url(url)
    build(nil).match_src(url)
  end

  # Public: Scans a given HTML document (either a String HTML fragment or
  # parsed GitHub::HTML document object).
  def self.scan(doc)
    build(doc).matches
  end

  # Public: Initializes an AssetScanner for the current environment.
  #
  # doc - Optional HTML document (either String HTML fragment or parsed
  #       GitHub::HTML document object). If not given, then only #match_src will
  #       work.
  def self.build(doc = nil)
    klass = if GitHub.s3_uploads_enabled?
      S3Scanner
    elsif GitHub.storage_cluster_enabled? || (Rails.env.test? && GitHub.enterprise?) # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      ClusterScanner
    else
      raise "Neither s3 nor cluster uploads are enabled"
    end
    klass.new(doc)
  end

  class S3Scanner < AssetScanner
    def match_src(src)
      patterns = [cdn_prod_data_s3_re, cdn_prod_data_private_images_s3_re, legacy_usercontent_asset_re, old_cloud_asset_re, legacy_s3_asset_re]

      if GitHub.include_alambic_asset_storage_paths?
        return match_development_asset(src)
      end

      if match = scan_url(src, *patterns)
        return MatchResult.match(*match)
      end

      if match = scan_url(src, canonical_re)
        return MatchResult.match(match[0], nil, match[1])
      end

      if match = scan_url(src, new_canonical_re)
        return MatchResult.match(nil, nil, match[0])
      end

      if match = scan_url(src, old_asset_re)
        return MatchResult.match(match[0], nil, match[1])
      end

      MatchResult.bad_patterns(patterns << old_asset_re)
    end

    private

    def match_development_asset(path)
      # Use new regex for private assets
      if private_image_asset?(path)
        user_id, asset_id, guid = scan_url(path, cdn_prod_data_private_images_s3_re)
        MatchResult.match(user_id, asset_id, guid)
      elsif canonical_asset?(path)
        user_id, guid = scan_url(path, canonical_re)
        MatchResult.match(user_id, nil, guid)
      else
        # Fall back to alambic asset matching
        guid = path.split("/").last
        user_id = scan_url(path, development_asset_re)
        MatchResult.match(user_id, nil, guid)
      end
    end

    def private_image_asset?(src)
      return false if src.nil?
      return false if GitHub.private_user_images_cdn_url.blank?
      src.match?(cdn_prod_data_private_images_s3_re)
    end

    def canonical_asset?(src)
      return false if src.nil?
      return true if src.match?(new_canonical_re)
      src.match?(canonical_re)
    end
  end

  class FileScanner < AssetScanner
    def match_src(src)
      if match = scan_url(src, file_asset_re)
        user_id = (match[0] + match[1]).to_i.to_s
        asset_id = (match[2] + match[3]).to_i.to_s
        return MatchResult.match(user_id, asset_id, match[4])
      end

      MatchResult.bad_patterns([file_asset_re])
    end
  end

  class ClusterScanner < FileScanner
    def match_src(src)
      patterns = [cluster_asset_re, private_cluster_asset_re, cluster_private_asset_re]
      if match = scan_url(src, *patterns)
        return MatchResult.match(match[0], nil, match[1])
      end

      if match = scan_url(src, new_cluster_private_asset_re)
        return MatchResult.match(nil, nil, match[0])
      end

      if GitHub.enterprise?
        mres = super(src)
        return mres if mres.success?
        return MatchResult.bad_patterns(patterns + mres.patterns)
      end

      MatchResult.bad_patterns(patterns)
    end
  end

  class Match
    attr_accessor :user_id, :asset_id, :asset_guid

    def initialize(user_id = nil, asset_id = nil, asset_guid = nil)
      @user_id = user_id
      @asset_id = asset_id
      @asset_guid = asset_guid
    end
  end

  class MatchResult
    attr_reader :match
    attr_reader :patterns

    def self.match(*args)
      new(Match.new(*args), [])
    end

    def self.bad_patterns(patterns)
      new(nil, patterns.compact)
    end

    def initialize(match, patterns)
      @match = match
      @patterns = patterns
    end

    def success?
      !@match.nil?
    end
  end

  attr_reader :doc

  def initialize(doc)
    @doc = GitHub::HTML.parse(doc)
    @matches = nil
  end

  def matches
    @matches || scan!
  end

  def scan!
    return if @matches

    @matches = []
    return @matches unless @doc.respond_to?(:search)

    @doc.search("img", "video").each do |media|
      src = media["data-canonical-src"] || media["src"]
      next unless src.respond_to?(:scan)
      mres = match_src(src)
      @matches << mres.match if mres.success?
    end

    @matches.freeze
    @matches
  end

  def scan_url(url, *regexes)
    regexes.compact.each do |regex|
      if !(match = url.scan(regex)).empty?
        return match[0]
      end
    end
    nil
  end

  def development_asset_re
    /http\:\/\/alambic\.github\.localhost\/storage\/user\/(\d+)\/files\/*/
  end

  # storage cluster url
  # http://172.28.128.4/download/user/123/files/guid
  def private_cluster_asset_re
    @private_cluster_asset_re ||= begin
      return unless root_url = GitHub.storage_private_mode_url
      %r{\A#{root_url}\/user\/(\d+)\/files\/([^\.\s]+)}
    end
  end

  # storage cluster url
  # http://172.28.128.4/storage/user/123/files/guid
  def cluster_asset_re
    @cluster_asset_re ||= begin
      %r{\A#{GitHub.storage_cluster_url}\/user\/(\d+)\/files\/([^\.\s]+)}
    end
  end

  # storage cluster private asset url
  # All private assets urls will end in `/assets/<user_id>/<guid>`
  # E.g: http://172.28.128.4/<user>/<repo>/assets/<user_id>/<guid>
  def cluster_private_asset_re
    @cluster_private_asset_re ||= begin
      %r{\/assets\/(\d+)\/(#{GitHub::Goomba::Async::AssetLoaders::AssetLoader::GUID_REGEX})}
    end
  end

  # new storage cluster private asset url
  # Under the new format private assets urls will end in `/user-attachments/assets/<guid>`
  # E.g: http://172.28.128.4/user-attachments/assets/<guid>
  def new_cluster_private_asset_re
    @new_cluster_private_asset_re ||= begin
      %r{\/user-attachments\/assets\/(#{GitHub::Goomba::Async::AssetLoaders::AssetLoader::GUID_REGEX})}
    end
  end

  def cdn_prod_data_s3_re
    return if GitHub.user_images_cdn_url.blank?
    @cdn_prod_data_s3_re ||= %r{\A#{GitHub.user_images_cdn_url}(\d+)\/(\d+)-([^\.]+)\.}
  end

  def canonical_re
    return if GitHub.url.blank?

    # In local dev, canonical URLs in image uploads contain :80 appended to them so regex
    # accounts for this and ignores port
    # example url structure : https://github.com/<owner>/<repo>/assets/<user_id>/<guid>
    # example url : https://github.com/Auth-Rewrite/test-stafftools-delete/assets/839181/8d7ffbbb-dc3d-4c7b-a0d8-7a655b818b47
    @canonical_re ||= %r{\A#{GitHub.url}(?::\d+)?\/[\w.-]+\/[\w.-]+\/assets\/(\d+)\/([^\.]+)}
  end

  def new_canonical_re
    return if GitHub.url.blank?

    # In local dev, canonical URLs in image uploads contain :80 appended to them so regex
    # accounts for this and ignores port
    # example url structure : https://github.com/user-attachments/assets/<guid>
    # example url : https://github.com/user-attachments/assets/8d7ffbbb-dc3d-4c7b-a0d8-7a655b818b47
    @new_canonical_re ||= %r{\A#{GitHub.url}(?::\d+)?\/user-attachments\/assets\/(#{GitHub::Goomba::Async::AssetLoaders::AssetLoader::GUID_REGEX})}
  end

  def cdn_prod_data_private_images_s3_re
    return if GitHub.private_user_images_cdn_url.blank?
    @cdn_prod_data_private_images_s3_re ||= %r{\A#{GitHub.private_user_images_cdn_url}\/(\d+)\/(\d+)-([^\.]+)\.}
  end

  # S3 url for legacy aws account
  # https://github-cloud.s3.amazonaws.com/assets/USER-ID/ASSET-ID/GUID.gif
  def legacy_s3_asset_re
    @legacy_s3_asset_re ||= %r{\A#{GitHub.s3_asset_host}#{GitHub.asset_base_path}\/(\d+)\/(\d+)\/([^\.]+)\.}
  end

  # user content url for legacy aws account
  # https://cloud.githubusercontent.com/assets/USER-ID/ASSET-ID/GUID.gif
  def legacy_usercontent_asset_re
    @legacy_usercontent_asset_re ||= %r{\Ahttps\:\/\/\w+\.githubusercontent\.com\/#{GitHub.asset_base_path}\/(\d+)\/(\d+)\/([^\.]+)\.}
  end

  # old cloud url (cloud.github.com subdomain varies by CDN, f = fastly)
  # https://f.cloud.github.com/assets/USER-ID/ASSET-ID/GUID.gif
  def old_cloud_asset_re
    @old_cloud_asset_re ||= %r{\Ahttps\:\/\/\w+\.cloud\.github\.com\/#{GitHub.asset_base_path}\/(\d+)\/(\d+)\/([^\.]+)\.}
  end

  # old S3 url
  # https://s3.amazonaws.com/github/assets/USER-ID/GUID-A/GUID-B/GUID.gif
  def old_asset_re
    @old_asset_re ||= /\Ahttps\:\/\/s3\.amazonaws\.com\/github\/#{GitHub.asset_base_path}\/(\d+)\/\w{2}\/\w{2}\/([^\.]+)./
  end

  # local file system url
  # /assets/USER-ID-A/USER-ID-B/ASSET-ID-A/ASSET-ID-B/GUID.gif
  # Kept since GHE still sets ENTERPRISE_FILE_ASSET_HOST
  def file_asset_re
    @file_asset_re ||= %r{\A#{GitHub.file_asset_host}/?#{GitHub.asset_base_path}\/(\d+)\/(\d+)\/(\d+)\/(\d+)\/([^\.]+)\.}
  end
end
