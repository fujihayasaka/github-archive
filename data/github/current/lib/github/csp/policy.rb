# typed: true
# frozen_string_literal: true

require_relative "../../../packages/code_rendering_service/app/models/viewscreen"
require_relative "../../../packages/code_rendering_service/app/models/notebook"

module GitHub::CSP::Policy
  # Public: File for defining CSP security directives for the Content Security
  # Policy header.

  # CDN host source.
  #
  # Return 'self' unless an asset host, on a different subdomain, is
  # configured.
  CDN_SOURCES = if GitHub.asset_host_url.blank? || !GitHub.subdomain_isolation?
    ["'self'"]
  elsif GitHub.ui_manifest_sha.present?
    ["'self'", GitHub.asset_host_url]
  else
    [GitHub.asset_host_url]
  end.uniq.freeze


  # Viewscreen, Notebooks, and main domain host source.
  if !GitHub.subdomain_isolation? && GitHub.enterprise?
    RENDER_SOURCE = ["'self'"]
  else
    # For multi-tenant-enterprise mode, we use tenant-specific needs dynamic CSP headers
    # that are set in the application controller
    # app/controllers/application_controller/security_headers_dependency.rb
    if GitHub.multi_tenant_enterprise?
      RENDER_SOURCE = []
    else
      RENDER_SOURCE = [Viewscreen.host_url,
        Notebook.host_url
      ].compact
    end
  end

  DEFAULT_SOURCES = [SecureHeaders::PolicyManagement::NONE].freeze

  # Allowed script URL allowlist.
  #
  # All hosts that we load scripts from needs to be part of this list.
  SCRIPT_SOURCES = [
    *CDN_SOURCES
  ].freeze

  # Allowed object URL allowlist.
  #
  # All hosts that we load objects from needs to be part of this list.
  OBJECT_SOURCES = [
    # No <object>, <embed>, or <applet> allowed.
  ].freeze

  # Allowed style URL allowlist.
  #
  # All hosts that we load styles from needs to be part of this list.
  STYLE_SOURCES = [
    SecureHeaders::PolicyManagement::UNSAFE_INLINE,
    *CDN_SOURCES,
  ].freeze

  # Alternative img-src configuration for multi tenant enterprise (report-only)
  IMG_SOURCES_MULTI_TENANT = [
    SecureHeaders::PolicyManagement::SELF,
    SecureHeaders::PolicyManagement::DATA_PROTOCOL,
    SecureHeaders::PolicyManagement::BLOB_PROTOCOL,
    *CDN_SOURCES,
    "*.#{GitHub.host_name}",
    GitHub.og_image_generator_base_url,
    ExploreFeed::CustomerStory::CUSTOMER_STORIES_FEED_URL,
    ExploreFeed::Spotlight::SPOTLIGHTS_FEED_URL,
  ].uniq

  IMG_SOURCES_MULTI_TENANT.freeze

  # Allowed image URL allowlist.
  #
  # All hosts that we load images from needs to be part of this list.
  if GitHub.restrict_external_images?
    IMG_SOURCES = [
      SecureHeaders::PolicyManagement::SELF,
      SecureHeaders::PolicyManagement::DATA_PROTOCOL,
      SecureHeaders::PolicyManagement::BLOB_PROTOCOL,
      *CDN_SOURCES,
      GitHub.alambic_assets_host,
      GitHub.storage_cluster_host,
      GitHub.image_proxy_url,
      GitHub.identicons_host,
      GitHub.alambic_avatar_url,
      GitHub.alambic_private_avatar_url,
      GitHub.s3_asset_bucket_host,
      GitHub.memory_alpha_fastly_url,
      GitHub.release_assets_fastly_url,
      GitHub.secured_user_images_cdn_url,
      GitHub.user_images_cdn_url,
      GitHub.private_user_images_cdn_url,
      GitHub.og_image_generator_base_url,
      GitHub.copilot_chat_attachment_azure_storage_base_url,
      "https://#{GitHub.s3_user_asset_new_host}",
      ExploreFeed::CustomerStory::CUSTOMER_STORIES_FEED_URL,
      ExploreFeed::Spotlight::SPOTLIGHTS_FEED_URL,
    ].uniq

    IMG_SOURCES << GitHub.memory_alpha_url if !GitHub.multi_tenant_enterprise?
    IMG_SOURCES.freeze
  else
    IMG_SOURCES = ["*", SecureHeaders::PolicyManagement::DATA_PROTOCOL, SecureHeaders::PolicyManagement::BLOB_PROTOCOL].freeze
  end

  def self.dynamic_img_sources
    if GitHub.restrict_external_images?
      [
        GitHub.urls.user_content_host_wildcard,
      ]
    else
      []
    end
  end

  # Allowed media URL allowlist.
  #
  # All hosts that we load audio and video from needs to be part of this list.
  if GitHub.multi_tenant_enterprise?
    media_sources = [*CDN_SOURCES]
  else
    media_sources = GitHub.video_asset_allowlist
  end
  MEDIA_SOURCES = media_sources.flatten.freeze

  # Allowed frame URL allowlist.
  #
  # All hosts that we load iframes for need to be part of this list.
  FRAME_SOURCES = [
    # Rendering Pages previews
    RENDER_SOURCE,
  ].flatten.freeze

  # Allowed font URL allowlist.
  #
  # All hosts that we load fonts needs to be part of this list.
  FONT_SOURCES = [
    *CDN_SOURCES,
  ].freeze

  # Third party connect sources.
  #
  # We allow a limited set of external connects on dotcom.
  # Also required in cluster mode on enterprise (Enterprise 2.4) to connect
  # to an external AWS S3 bucket URL.
  if GitHub.allow_third_party_connect_sources?
    # Enterprise clusters configure this via env variables and only needs a single
    # source (String).
    THIRD_PARTY_CONNECT_SOURCES = Array(GitHub.third_party_connect_sources)
  else
    THIRD_PARTY_CONNECT_SOURCES = [].freeze
  end

  # Allowed connect URL allowlist.
  #
  # All hosts that we make XHR requests to needs to be part of this list.
  CONNECT_SOURCES = [
    SecureHeaders::PolicyManagement::SELF,
    GitHub.alambic_csp_host,
    GitHub.storage_cluster_host,
    GitHub.site_status_url,
    GitHub.collector_public_url,
    GitHub.livereload_url,
    GitHub.webpack_dev_server_connect_url,
    GitHub.urls.raw_host_name,

    # Only paths allowlisted in Api::App::Cors are allowed from GitHub.com.
    GitHub.api_host_name,

    THIRD_PARTY_CONNECT_SOURCES,
    *CDN_SOURCES # Needed to allow sourcemaps to load in browser devtools.
  ].flatten.uniq.compact

  CONNECT_SOURCES << GitHub.memory_alpha_url if !GitHub.multi_tenant_enterprise?

  # Copilot Proxy
  if GitHub.copilot_enabled?
    # Legacy URL
    CONNECT_SOURCES << "https://copilot-proxy.githubusercontent.com"

    # SKU Isolation
    %w[individual business enterprise].each do |plan|
      CONNECT_SOURCES << "https://proxy.#{plan}.githubcopilot.com"
    end
  end

  CONNECT_SOURCES.freeze

  def self.dynamic_connect_src
    return @dynamic_connect_src if defined?(@dynamic_connect_src)

    urls = []
    urls << GitHub.urls.alive_ws_url

    if copilot_api_override_url = GitHub.copilot_api_override_url
      urls << copilot_api_override_url
    end

    # Copilot API
    if GitHub.copilot_enabled?
      if GitHub.multi_tenant_enterprise?
        # Proxima URL
        urls << "https://copilot-api.#{GitHub.host_name_with_tenant}"
      else
        # Legacy URL
        urls << "https://api.githubcopilot.com"

        # SKU Isolation
        %w[individual business enterprise].each do |plan|
          urls << "https://api.#{plan}.githubcopilot.com"
        end
      end
    end

    return urls if GitHub.multi_tenant_enterprise?

    @dynamic_connect_src = urls
  end

  WORKER_CDN_PATH = "/assets-cdn/worker/".freeze
  WEBPACK_PATH = "/webpack/".freeze
  VITE_PATH = "/vite/".freeze
  ASSETS_PATH = "/assets/".freeze

  WORKER_SOURCES = [
    *CDN_SOURCES,
    "#{GitHub.host_name}#{WORKER_CDN_PATH}",
    *("#{GitHub.host_name}#{WEBPACK_PATH}" if Rails.env.development?),
    *("#{GitHub.host_name}#{VITE_PATH}" if Rails.env.development?),
    "#{GitHub.host_name}#{ASSETS_PATH}",
    "#{GitHub.gist3_host_name}#{WORKER_CDN_PATH}",
    # If we have a separate admin host and we're on a node serving that domain,
    # we also allow this in the worker-src. This is so that we don't expose this
    # domain existing outside of when it is configured.
    GitHub.admin_host_name && GitHub.role == :stafftools ? "#{GitHub.admin_host_name}#{WORKER_CDN_PATH}" : nil,
  ].compact.uniq.freeze

  # `child-src` is set to the same values as `worker-src` since Safari doesn't
  # support the `worker-src` directive.
  CHILD_SOURCES = WORKER_SOURCES

  def self.dynamic_worker_src
    ["#{GitHub.host_name_with_tenant}#{WORKER_CDN_PATH}"]
  end

  # Allowed base URIs.
  #
  # The base should always be self.
  BASE_URI_SOURCES = [
    SecureHeaders::PolicyManagement::SELF,
  ].freeze

  # Allowed form action="" URL allowlist.
  #
  # All hosts that we post form requests to need to be part of this list.
  FORM_ACTIONS = [
    SecureHeaders::PolicyManagement::SELF,
    GitHub.host_name,
    GitHub.gist3_host_name,
    GitHub.auth.cas? ? GitHub.cas_host : nil, # Needed for CAS logout.
    GitHub.copilot_workspace_host_name,
  ].flatten

  FORM_ACTIONS << GitHub.memory_alpha_url if !GitHub.multi_tenant_enterprise?
  FORM_ACTIONS.freeze

  PLUGIN_TYPES = [
    # No plugins allowed.
  ].freeze

  FRAME_ANCESTORS = [
    SecureHeaders::PolicyManagement::NONE,
  ].freeze

  MANIFEST_SOURCES = [
    SecureHeaders::PolicyManagement::SELF,
  ].freeze
end
