#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

require "pathname"
require "json"
require "find"
require "uri"
require "net/http"

require_relative "../config/basic"
require "azure/storage/blob"

class UploadStaticUIAssets
  IGNORED_ASSET_PATTERNS = [
    /^manifest\./,
    /^ui-manifest\..*\.json$/
  ].freeze

  WEB_CONTAINER_URL = "https://staticuiassets.blob.core.windows.net/$web"
  CHUNK_SIZE = 5

  class Stats
    attr_accessor :uploaded, :exists, :ignored

    def initialize
      @uploaded = 0
      @exists = 0
      @ignored = 0
    end
  end

  def initialize
    @root_path = File.expand_path("..", __dir__)
    @public_directory = Pathname.new(File.join(@root_path, "public"))
    @client_id = ENV["SPN_STATIC_UI_ASSETS_GITHUB_CI_CLIENT_ID"]
    @tenant_id = ENV["SPN_STATIC_UI_ASSETS_GITHUB_CI_TENANT_ID"]
    @client_secret = ENV["SPN_STATIC_UI_ASSETS_GITHUB_CI"]
    @storage_account_name = ENV["AZURE_STORAGE_ACCOUNT"] || extract_storage_account_name

    validate_credentials!
    setup_azure_client
  end

  def run
    upload_start = Time.now

    assets = collect_assets
    stats = Stats.new

    puts "Found #{assets.length} assets to process"

    # Process assets in chunks to avoid overwhelming the API
    assets.each_slice(CHUNK_SIZE) do |asset_chunk|
      threads = asset_chunk.map do |asset|
        Thread.new { upload_asset(asset, stats) }
      end

      # Wait for all uploads in this chunk to complete
      threads.each(&:join)
    end

    upload_duration = Time.now - upload_start

    puts "---------------------------------------"
    puts "⬆️  Uploaded #{stats.uploaded} new assets"
    puts "✨ Skipped #{stats.exists} existing assets"
    puts "⏭️  Ignored #{stats.ignored} assets"
    puts "🚀 Done syncing #{assets.length} assets (#{upload_duration.round(2)}s)"
  end

  private

  def validate_credentials!
    # Check for required Service Principal credentials
    unless @client_id && @tenant_id && @client_secret
      missing = []
      missing << "SPN_STATIC_UI_ASSETS_GITHUB_CI_CLIENT_ID" unless @client_id
      missing << "SPN_STATIC_UI_ASSETS_GITHUB_CI_TENANT_ID" unless @tenant_id
      missing << "SPN_STATIC_UI_ASSETS_GITHUB_CI" unless @client_secret

      raise "Missing Service Principal credentials: #{missing.join(', ')}"
    end
  end

  # Simple Azure credential provider
  class ClientSecretCredential
    def initialize(tenant_id:, client_id:, client_secret:)
      @tenant_id = tenant_id
      @client_id = client_id
      @client_secret = client_secret
      @token = nil
      @token_expires_at = nil
    end

    def get_access_token
      # Return cached token if still valid
      if @token && @token_expires_at && Time.now < @token_expires_at - 60
        return @token
      end

      # Get new token from Azure
      token_url = "https://login.microsoftonline.com/#{@tenant_id}/oauth2/v2.0/token"

      uri = URI(token_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"

      params = {
        "grant_type" => "client_credentials",
        "client_id" => @client_id,
        "client_secret" => @client_secret,
        "scope" => "https://storage.azure.com/.default"
      }

      request.body = URI.encode_www_form(params)
      response = http.request(request)

      unless response.code == "200"
        raise "Failed to get Azure token: #{response.code} #{response.message}\nResponse: #{response.body}"
      end

      token_data = JSON.parse(response.body)
      @token = token_data["access_token"]
      expires_in = token_data["expires_in"].to_i
      @token_expires_at = Time.now + expires_in

      @token
    end
  end

  def setup_azure_client
    credential = ClientSecretCredential.new(
      tenant_id: @tenant_id,
      client_id: @client_id,
      client_secret: @client_secret
    )

    # Get access token
    access_token = credential.get_access_token

    # Create Azure Storage client with token authentication
    token_credential = ::Azure::Storage::Common::Core::TokenCredential.new(access_token)
    token_signer = ::Azure::Storage::Common::Core::Auth::TokenSigner.new(token_credential)

    @blob_service = ::Azure::Storage::Blob::BlobService.create({
      storage_account_name: @storage_account_name,
      signer: token_signer
    })
  end

  def extract_storage_account_name
    # Extract storage account name from URL
    # https://staticuiassets.blob.core.windows.net/$web -> staticuiassets
    URI.parse(WEB_CONTAINER_URL).host.split(".").first
  end

  def collect_assets
    assets = []

    Find.find(@public_directory) do |path|
      next if File.directory?(path)

      # Convert absolute path to relative path from public directory
      relative_path = Pathname.new(path).relative_path_from(@public_directory).to_s
      assets << relative_path
    end

    assets
  end

  def ignored_asset?(asset_path)
    filename = File.basename(asset_path)
    IGNORED_ASSET_PATTERNS.any? { |pattern| filename.match?(pattern) }
  end

  def get_content_type(asset_path)
    extension = File.extname(asset_path).downcase

    content_types = {
      ".css" => "text/css",
      ".js" => "application/javascript",
      ".json" => "application/json",
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif" => "image/gif",
      ".svg" => "image/svg+xml",
      ".ico" => "image/x-icon",
      ".woff" => "font/woff",
      ".woff2" => "font/woff2",
      ".ttf" => "font/ttf",
      ".eot" => "application/vnd.ms-fontobject",
      ".html" => "text/html",
      ".xml" => "application/xml",
      ".txt" => "text/plain"
    }

    content_types[extension] || "application/octet-stream"
  end

  def upload_asset(asset, stats)
    if ignored_asset?(asset)
      puts "⏭️  Ignoring #{asset}"
      stats.ignored += 1
      return
    end

    container_name = "$web"

    # Check if blob already exists
    begin
      blob_properties = @blob_service.get_blob_properties(container_name, asset)
      if blob_properties
        puts "✨ Skipping #{asset} (already exists)"
        stats.exists += 1
        return
      end
    rescue Azure::Core::Http::HTTPError => e
      # 404 means the blob doesn't exist, which is what we want
      raise unless e.status_code == 404
    end

    content_type = get_content_type(asset)
    puts "⬆️  Uploading #{asset} as #{content_type}"

    upload_start = Time.now

    # Read file content
    file_path = @public_directory.join(asset)
    content = File.read(file_path)

    # Determine cache settings
    is_cacheable = asset.start_with?("assets/")
    cache_control = is_cacheable ? "public, max-age=31536000, immutable" : nil

    # Upload to blob storage
    options = {
      content_type: content_type
    }
    options[:cache_control] = cache_control if cache_control

    @blob_service.create_block_blob(container_name, asset, content, options)

    duration = Time.now - upload_start
    puts "✅ Uploaded #{asset} (#{duration.round(2)}s)"
    stats.uploaded += 1

  rescue => error
    puts "❌ Failed to upload #{asset}: #{error.message}"
    raise
  end
end

if __FILE__ == $0
  begin
    UploadStaticUIAssets.new.run
  rescue => error
    # Log formatted error for build pipelines to pick up
    puts "===ERROR==="
    puts JSON.pretty_generate({ error: error.message })
    puts "===END ERROR==="

    # Log unformatted error to get full stacktrace in the logs
    puts error.full_message

    # Exit with non-zero exit code so the ci job fails
    exit 1
  end
end
