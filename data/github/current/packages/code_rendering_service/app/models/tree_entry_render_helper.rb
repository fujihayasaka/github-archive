# typed: true
# frozen_string_literal: true

module TreeEntryRenderHelper

  extend T::Helpers
  requires_ancestor { TreeEntry }

  sig do
    params(
      viewer: T.nilable(User),
      repository: Repository,
      ref: String, path: String,
      expires_key: T.nilable(Symbol),
      host: T.nilable(String),
      query: T::Hash[Symbol, T.untyped]
    )
    .returns(String)
  end
  def self.raw_blob_url(viewer, repository, ref, path, expires_key: nil, host: nil, query: {})
    expires_key ||= :render

    needs_a_token = (repository.private?) ||
                    (GitHub.enterprise? && GitHub.private_mode_enabled?)
    if viewer && needs_a_token
      scope = RawBlob.scope(repository, ref, path)
      query[:token] = RawBlob.token(repository, scope, expires_key, user: viewer)
    end

    query[:lab] = true if GitHub.employee_unicorn?

    host ||= GitHub.urls.raw_host_name || GitHub.render_raw_host_name
    prefix = if host
      "#{GitHub.scheme}://#{host}"
    else
      "#{GitHub.scheme}://#{GitHub.host_name}/raw"
    end

    file_name = path.include?("/") ? path.partition("/").last : path
    # check if filename with valid extension or if the filename simply contains a #
    # ex. test/#filename0.png vs test/filename0.png#fragment
    split_at_hash = file_name.split("#")[0]
    contains_fragment = file_name.include?("#") && !split_at_hash.nil? && !File.extname(split_at_hash).empty?
    path, _hash, fragment = path.rpartition("#") if contains_fragment

    url = [
      prefix,
      repository.name_with_display_owner,
      *ref.split("/").map! { |p| UrlHelper.escape_path(p) },
      *path.split("/").map! { |p| maybe_escape_path_fragment(p) },
    ].join("/")
    url << "?#{query.to_query}" unless query.empty?
    url << "##{fragment}" if fragment
    url
  end

  def self.maybe_escape_path_fragment(fragment)
    return fragment unless URI.decode_www_form_component(fragment) == fragment

    UrlHelper.escape_path(fragment)
  rescue ArgumentError # i.e. invalid %-encoding
    UrlHelper.escape_path(fragment)
  end

  sig { params(viewer: T.nilable(User), gist: Gist, commit_oid: String, path: String).returns(String) }
  def self.raw_gist_url(viewer, gist, commit_oid, path)
    file = path.sub(/\A\//, "")

    if viewer && GitHub.private_mode_enabled?
      scope = "Gist:#{gist.user_param}/#{gist.repo_name}/#{commit_oid}/#{file}"
      token = viewer.signed_auth_token(scope: scope, expires: RawBlob::EXPIRES[:blob].from_now)
    end

    scheme = GitHub.scheme
    host = GitHub.subdomain_isolation ? GitHub.urls.raw_host_name : GitHub.host_name

    path = [
      GitHub.subdomain_isolation? ? nil : %w(raw),
      "gist",
      UrlHelper.escape_path(gist.user_param),
      UrlHelper.escape_path(gist.repo_name),
      "raw",
      UrlHelper.escape_path(commit_oid),
      UrlHelper.escape_path(file),
    ].compact.join("/")

    query_string = token ? "?#{{ token: token }.to_query}" : ""

    "#{scheme}://#{host}/#{path}#{query_string}"
  end

  # Construct a URL for reading LFS blob content. Note that some very different
  # request paths and authorization schemes diverge here:
  #
  # 1. When storage_cluster_enabled? (GHES), this request is directed to
  #    alambic's storage cluster, which will serve the content from disk.
  #
  # 2. On dotcom (the media_blob_url case), the request is for the
  #    media.githubusercontent.com fastly CDN, which routes to alambic, which
  #    then fetches the content from memory-alpha, which itself fetches it from
  #    s3 (or ABS?)
  #
  # In both of the above cases, alambic checks the
  # /internal/assets/media/:user/:repo/?* API which applies `get_media_blob`
  # access control. (see
  # https://github.com/github/github/pull/293742#discussion_r1424967555 for
  # more detail). On Proxima, however, we have:
  #
  # 3. When multi_tenant_enterprise?, lfs_blob_url creates an
  #    objects-origin.<tenant>.ghe.com url, which embeds a time-limited access
  #    token and points directly at memory-alpha.
  #
  # In this case, the monolith is no longer in the request path, so the access
  # control is determined by the caller.

  sig { params(viewer: T.nilable(User), repository: Repository, ref: String, path: String, oid: String).returns(String) }
  def self.lfs_blob_url(viewer, repository, ref, path, oid)
    if GitHub.storage_cluster_enabled?
      return storage_cluster_url(viewer, repository, ref, path)
    end

    if GitHub.flipper[:lfs_proxima_memory_alpha_blob_urls].enabled?(repository)
      if GitHub.multi_tenant_enterprise? || Rails.env.development?
        return Media::Blob.fetch(repository, oid).download_url(actor: viewer, repo: repository)
      end
    end

    media_blob_url(viewer, repository, ref, path)
  end

  sig { params(viewer: T.nilable(User), repository: Repository, ref: String, path: String).returns(String) }
  def self.storage_cluster_url(viewer, repository, ref, path)
    path_info = [
      "raw_lfs",
      repository.name_with_owner,
      *ref.split("/").map! { |p| UrlHelper.escape_path(p) },
      *path.split("/").map! { |p| UrlHelper.escape_path(p) },
    ].join("/")

    url = "#{GitHub.storage_cluster_url}/#{path_info}".dup
    return url if repository.public? && !GitHub.private_mode_enabled?
    scope = RawBlob.scope(repository, ref, path)
    token = RawBlob.token(repository, scope, :render, user: viewer)
    url << "?#{{ token: token }.to_query}"
  end

  sig { params(viewer: T.nilable(User), repository: Repository, ref: String, path: String).returns(String) }
  def self.media_blob_url(viewer, repository, ref, path)
    url = [
      GitHub.alambic_assets_url,
      "media",
      repository.name_with_owner,
      *ref.split("/").map! { |p| UrlHelper.escape_path(p) },
      *path.split("/").map! { |p| UrlHelper.escape_path(p) },
    ].join("/")

    return url if repository.public? && !GitHub.private_mode_enabled?

    scope = Media::Blob.auth_scope_options(repository, ref, path)
    token = Media::Blob.auth_token(viewer, scope)
    url << "?#{{ token: token }.to_query}"
  end

  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.solid?(blob)
    blob.extname.downcase == ".stl"
  end

  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.geojson?(blob)
    extension = blob.extname.downcase
    if %w(.geojson .topojson).include?(extension)
      GitHub.dogstats.increment "blob", tags: ["action:geojson", "type:.geo#{extension}"]
      true
    elsif extension == ".json"
      # If the blob doesn't have a repository, we won't be able to load the
      # data to check if its a GeoJSON .json file
      if blob.repository && blob.data =~ %r{"type"\s*:\s*"(featurecollection|topology|geometrycollection)"}i
        GitHub.dogstats.increment "blob", tags: ["action:geojson", "type:geo.json"]
        true
      else
        false
      end
    else
      false
    end
  end

  # Topojson is a subset of geojson that we can't diff, yet.
  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.topojson?(blob)
    extension = blob.extname.downcase
    if extension == ".topojson"
      true
    elsif extension == ".json"
      # If the blob doesn't have a repository, we won't be able to load the
      # data to check if its a GeoJSON .json file
      if blob.repository && blob.data =~ %r{"type"\s*:\s*"topology"}i
        true
      else
        false
      end
    else
      false
    end
  end

  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.img?(blob)
    blob.image?
  end

  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.psd?(blob)
    blob.extname.downcase == ".psd"
  end

  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.svg?(blob)
    blob.extname.downcase == ".svg"
  end

  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.pdf?(blob)
    blob.extname.downcase == ".pdf"
  end

  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.ipynb?(blob)
    blob.extname.downcase == ".ipynb"
  end

  sig { params(blob: TreeEntry).returns(T::Boolean) }
  def self.mermaid?(blob)
    ext = blob.extname.downcase
    ext == ".mmd" || ext == ".mermaid"
  end

  # Internal: Detect render file type for tree entry file.
  #
  # Returns symbol file type or nil.
  sig { returns(T.nilable(Symbol)) }
  def render_type
    return nil unless GitHub.render_enabled?

    return @render_type if defined? @render_type

    if symlink?
      return @render_type = nil
    end

    T.bind(self, TreeEntry)
    @render_type = if TreeEntryRenderHelper.solid?(self)
      :solid
    elsif TreeEntryRenderHelper.pdf?(self)
      :pdf
    elsif TreeEntryRenderHelper.topojson?(self)
      :topojson
    elsif TreeEntryRenderHelper.geojson?(self)
      :geojson
    elsif TreeEntryRenderHelper.ipynb?(self)
      :ipynb
    elsif TreeEntryRenderHelper.psd?(self)
      :psd
    elsif TreeEntryRenderHelper.svg?(self)
      :svg
    elsif TreeEntryRenderHelper.img?(self)
      :img
    else
      nil
    end

    if @render_type && GitHub.render_type_filter.any?
      # If filters are set, require type to be allowlisted
      # Primarily used for Enterprise where some formats are disabled
      unless GitHub.render_type_filter.include?(@render_type.to_s)
        @render_type = nil
      end
    end

    @render_type
  end

  # From Render::App
  #   https://github.com/github/render/blob/master/app/render.rb
  RENDER_COMMON_TYPES = [:solid, :geojson, :psd, :svg]
  RENDER_VIEW_TYPES = RENDER_COMMON_TYPES + [:pdf, :ipynb, :topojson]
  RENDER_DIFF_TYPES = (RENDER_COMMON_TYPES + [:img])
  RENDER_PREVIEW_TYPES = [:geojson, :topojson]
  RENDER_IMAGE_TYPES = [:psd, :svg, :img]

  # Public: Detect render file for a given display context.
  #
  # Not all file types support all display contexts. For an example, PDF can
  # be viewed readonly but not diffed.
  #
  # Returns symbol file type or nil.

  sig { params(display_type: Symbol, viewer: T.nilable(User)).returns(T.nilable(Symbol)) }
  def render_file_type_for_display(display_type, viewer: nil)
    return nil unless GitHub.render_enabled?

    type = render_type

    case display_type
    when :view
      type if RENDER_VIEW_TYPES.include?(type)
    when :diff
      type if RENDER_DIFF_TYPES.include?(type)
    when :preview
      type if RENDER_PREVIEW_TYPES.include?(type)
    else
      type
    end
  end

  private

  # Encode the URL as a hex string to never have to worry about
  # any character encoding not matching what we can send in URL
  #
  # Returns a String
  sig { params(url: String).returns(String) }
  def render_encode_url(url)
    url.to_s.unpack1("H*")
  end
end
