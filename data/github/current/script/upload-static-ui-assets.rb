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
  CONCURRENCY = 100

  class Stats
    attr_accessor :uploaded, :exists, :ignored, :retries

    def initialize
      @uploaded = 0
      @exists = 0
      @ignored = 0
      @retries = 0
    end
  end

  OIDC_AUDIENCE = "api://AzureADTokenExchange"

  def initialize
    @root_path = File.expand_path("..", __dir__)
    @public_directory = Pathname.new(File.join(@root_path, "public"))
    @client_id = ENV["SPN_STATIC_UI_ASSETS_GITHUB_CI_CLIENT_ID"]
    @tenant_id = ENV["SPN_STATIC_UI_ASSETS_GITHUB_CI_TENANT_ID"]
    @oidc_request_url = ENV["ACTIONS_ID_TOKEN_REQUEST_URL"]
    @oidc_request_token = ENV["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]
    @storage_account_name = ENV["AZURE_STORAGE_ACCOUNT"] || extract_storage_account_name
    @upload_retry_max = ENV.fetch("ASSET_UPLOAD_RETRY_MAX", "3").to_i

    validate_credentials!
    setup_azure_client
  end

  def run
    upload_start = Time.now

    assets = collect_assets
    stats = Stats.new

    puts "Found #{assets.length} assets to process"

    # Use a worker pool so a slow upload doesn't block the rest of the chunk.
    # Workers pull from a shared queue until it's drained.
    queue = Queue.new
    assets.each { |asset| queue << asset }

    worker_count = [CONCURRENCY, assets.length].min
    workers = Array.new(worker_count) do
      Thread.new do
        loop do
          asset = queue.pop(true) rescue nil
          break if asset.nil?
          upload_asset(asset, stats)
        end
      end
    end

    workers.each(&:join)

    upload_duration = Time.now - upload_start

    puts "---------------------------------------"
    puts "⬆️  Uploaded #{stats.uploaded} new assets"
    puts "✨ Skipped #{stats.exists} existing assets"
    puts "⏭️  Ignored #{stats.ignored} assets"
    puts "🔄 Retried #{stats.retries} times"
    puts "🚀 Done syncing #{assets.length} assets (#{upload_duration.round(2)}s)"
  end

  private

  def validate_credentials!
    missing = []
    missing << "SPN_STATIC_UI_ASSETS_GITHUB_CI_CLIENT_ID" unless @client_id
    missing << "SPN_STATIC_UI_ASSETS_GITHUB_CI_TENANT_ID" unless @tenant_id
    missing << "ACTIONS_ID_TOKEN_REQUEST_URL" unless @oidc_request_url
    missing << "ACTIONS_ID_TOKEN_REQUEST_TOKEN" unless @oidc_request_token

    raise "Missing credentials: #{missing.join(', ')}" unless missing.empty?
  end

  # Fetches a GitHub Actions OIDC token and exchanges it for an Azure AD access token
  # using the client assertion (federated credential) flow.
  class OidcCredential
    def initialize(tenant_id:, client_id:, oidc_request_url:, oidc_request_token:, audience:)
      @tenant_id = tenant_id
      @client_id = client_id
      @oidc_request_url = oidc_request_url
      @oidc_request_token = oidc_request_token
      @audience = audience
      @token = nil
      @token_expires_at = nil
    end

    def get_access_token
      # Return cached token if still valid (with 60s buffer)
      if @token && @token_expires_at && Time.now < @token_expires_at - 60
        return @token
      end

      # Get a GitHub Actions OIDC JWT
      oidc_jwt = fetch_oidc_token

      # Exchange the OIDC JWT for an Azure AD access token
      exchange_for_azure_token(oidc_jwt)
    end

    private

    def fetch_oidc_token
      uri = URI(@oidc_request_url)
      uri.query = URI.encode_www_form({ "audience" => @audience })

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "bearer #{@oidc_request_token}"
      request["Content-Type"] = "application/json"
      request["User-Agent"] = "github/upload-static-ui-assets"

      response = http.request(request)

      unless response.code == "200"
        raise "Failed to get GitHub Actions OIDC token: #{response.code} #{response.message}\nResponse: #{response.body}"
      end

      data = JSON.parse(response.body)
      token = data["value"]
      raise "GitHub Actions OIDC response missing 'value'" unless token

      token
    end

    def exchange_for_azure_token(oidc_jwt)
      token_url = "https://login.microsoftonline.com/#{@tenant_id}/oauth2/v2.0/token"

      uri = URI(token_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/x-www-form-urlencoded"

      params = {
        "grant_type" => "client_credentials",
        "client_id" => @client_id,
        "client_assertion_type" => "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
        "client_assertion" => oidc_jwt,
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
    credential = OidcCredential.new(
      tenant_id: @tenant_id,
      client_id: @client_id,
      oidc_request_url: @oidc_request_url,
      oidc_request_token: @oidc_request_token,
      audience: OIDC_AUDIENCE
    )

    # Fetch the access token once on the main thread; workers will share the
    # immutable token string but each build their own BlobService.
    @access_token = credential.get_access_token

    # A BlobService used only from the main thread for one-off setup checks.
    @blob_service = build_blob_service
  end

  # Azure::Storage::Blob::BlobService is *not* thread-safe -- the gem mutates
  # shared header/signer state during each request, so concurrent calls on a
  # single instance scramble headers and produce spurious 404s. Give every
  # worker its own client.
  def build_blob_service
    token_credential = ::Azure::Storage::Common::Core::TokenCredential.new(@access_token)
    token_signer = ::Azure::Storage::Common::Core::Auth::TokenSigner.new(token_credential)

    ::Azure::Storage::Blob::BlobService.create({
      storage_account_name: @storage_account_name,
      signer: token_signer
    })
  end

  def thread_blob_service
    Thread.current[:blob_service] ||= build_blob_service
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
    # Speculation Rules file needs special MIME type
    return "application/speculationrules+json" if asset_path.match?(/\.specrule-\w+\.json$/)

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
    retry_count = 0
    blob_service = thread_blob_service

    begin
      # Check if blob already exists. Assets are content-hashed so on most runs
      # the vast majority will already be present -- a cheap HEAD avoids the
      # full PUT body for those.
      begin
        if blob_service.get_blob_properties(container_name, asset)
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

      file_path = @public_directory.join(asset)

      # Determine cache settings
      is_cacheable = asset.start_with?("assets/")
      cache_control = is_cacheable ? "public, max-age=31536000, immutable" : nil

      options = {
        content_type: content_type,
      }

      options[:cache_control] = cache_control if cache_control

      # Stream the file straight from disk instead of slurping it into memory.
      File.open(file_path, "rb") do |io|
        blob_service.create_block_blob(container_name, asset, io, options)
      end

      duration = Time.now - upload_start
      puts "✅ Uploaded #{asset} (#{duration.round(2)}s)"
      stats.uploaded += 1
    rescue => error
      if retry_count < @upload_retry_max
        # Exponential backoff: 100ms, 1s, 10s (matches the TS uploader)
        delay = (10**retry_count) * 0.1
        puts "⚠️  Failed to upload #{asset}: #{error.message} -- retrying in #{delay}s (attempt #{retry_count + 1}/#{@upload_retry_max})"
        stats.retries += 1
        retry_count += 1
        sleep(delay)
        retry
      end

      puts "❌ Failed to upload #{asset}: #{error.message}"
      raise
    end
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
