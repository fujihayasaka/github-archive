# typed: true
# frozen_string_literal: true

module Api::App::RepositoryContentHelpers
  extend T::Helpers

  requires_ancestor { Api::App }
  requires_ancestor { Api::RepositoryContents }

  include GitHub::Memoizer

  def serve_contents_with_spokes!
    GitHub.tracer.in_span("api.app.repository-content-helpers", kind: :internal, attributes: {
      "code.namespace" => "serve_contents_with_spokes"
    }) do |_span|
      # handle paths that end in /
      if content_path.ends_with?("/")
        redirect(api_url(request.path[0..-2]))
      end

      begin
        if content_metadata.empty_repository?
          deliver_error!(404,
            message: "This repository is empty.",
            documentation_url: "/v3/repos/contents/#get-contents")
        elsif content_metadata.commit_not_found?
          deliver_error!(404,
            message: "No commit found for the ref #{ref_name}",
            documentation_url: "/v3/repos/contents/")
        elsif content_metadata.tree_not_found?
          deliver_error!(404,
            message: "No commit found for the ref #{ref_name}",
            documentation_url: "/v3/repos/contents/")
        elsif content_metadata.object_not_found?
          deliver_error!(404)
        end

        if content_metadata.tree?
          deliver_tree_contents_spokes!
        elsif content_metadata.submodule?
          deliver_submodule_contents_spokes!
        else # blob
          deliver_blob_contents_spokes!
        end
      rescue SpokesAPI::NotFound, SpokesAPI::InvalidArgument, SpokesAPI::TwirpServerError => e
        GitHub.logger.error(
          e.message,
          "code.namespace": "Api::App::RepositoryContentHelpers",
          "code.function": "serve_contents_with_spokes!",
          "gh.user.id": current_user&.id,
          "gh.request_id": GitHub.context[:request_id],
        )
        deliver_error!(404)
      rescue SpokesAPI::ResourceExhausted => err
        deliver_error!(429, message: err.message)
      end
    end
  end

  def content_metadata
    return @content_metadata if defined?(@content_metadata)

    @content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: current_repository,
      ref: ref_name,
      path: normalized_path,
    )

    @content_metadata
  end

  def deliver_submodule_contents_spokes!
    last_modified = calc_last_modified_for_object(current_repository)

    # Give Sinatra a chance to halt immediately if ETag matches.
    set_caching_headers!({ etag: content_metadata.root_tree_entry_oid, last_modified: last_modified })

    deliver :content_hash,
      submodule_tree_entry,
      repo: current_repository,
      full: true,
      ref: ref_name
  end

  def deliver_blob_contents_spokes!
    # Give Sinatra a chance to halt immediately if ETag matches.
    last_modified = current_commit_last_modified
    if last_modified.present?
      set_caching_headers!({ etag: content_metadata.path_object_oid, last_modified: last_modified })
    end

    # Make sure the blob is not too large
    blob_size = content_metadata.path_object_size
    if blob_size > Api::RepositoryContents::MAX_BLOB_SIZE
      deliver_too_large_error!(blob_size)
    end
    if blob_size > Api::RepositoryContents::RAW_OBJECT_ONLY_BLOB_SIZE && medias.api_param?(:html)
      deliver_too_large_error!(blob_size)
    end

    blob = spokes_blob
    if blob.nil?
      deliver_error!(404)
    end

    GitHub.dogstats.increment("repos.api.get_repo_contents", tags: get_blob_tags(true, blob, medias))

    if medias.api_param?(:raw)
      blob_to_use = blob.symlink_target || blob

      deliver_raw blob_to_use.data, content_type: "#{medias}; charset=utf-8"
    elsif medias.api_param?(:html)
      blob_to_use = blob.symlink_target || blob
      blob_to_use.info["path"] = blob.path

      deliver_raw render_file(blob_to_use, content_path, "file"), content_type: "#{medias}; charset=utf-8"
    else

      deliver :content_hash, blob,
        repo: current_repository,
        full: true,
        ref: ref_name,
        sha: content_metadata.root_tree_entry_oid
    end
  end

  def current_commit_last_modified
    return @current_commit_last_modified if defined?(@current_commit_last_modified)

    Repositories.domain.contents.get_commit_date(
      repository: current_repository,
      oid: content_metadata.ref_commit_oid
    )
  end

  def spokes_blob
    return @spokes_blob if defined?(@spokes_blob)

    blob_contents = Repositories.domain.contents.blob_by_path_and_metadata(
      repository: current_repository,
      metadata: content_metadata,
      path: normalized_path,
      load_full_content: medias.api_param?(:raw)
    )

    return nil unless blob_contents

    @spokes_blob = tree_entry_from_blob(blob: blob_contents)
  end

  # This conversion is needed currently as a shim to enable the html rendering pipeline to work.
  # The Goomba code relies on logic in TreeEntry.
  sig { params(blob: Repositories::Contents::Blob).returns(TreeEntry) }
  def tree_entry_from_blob(blob:)
    tree_entry = TreeEntry.new(current_repository, tree_entry_data_hash(blob:))

    if symlink = blob.symlink_target
      tree_entry.info["symlink_target"] = symlink.oid
      tree_entry.info["symlink_target_object"] = tree_entry_data_hash(blob: symlink)
    end

    tree_entry
  end

  sig { params(blob: Repositories::Contents::Blob).returns(T::Hash[String, T.untyped]) }
  def tree_entry_data_hash(blob:)
    {
      "type" => "blob",
      "oid"  => blob.oid,
      "mode" => blob.mode,
      "name" => blob.name,
      "path" => blob.path,
      "size" => blob.size,
      "data" => blob.truncated? ? "" : blob.contents, # this is for compatibility with TreeEntry, which omits the data if it's too large
      "encoding" => blob.encoding,
      "binary" => blob.binary?,
      "truncated" => blob.truncated?,
    }
  end

  def deliver_tree_contents_spokes!
    GitHub.tracer.in_span("api.app.repository-contents", kind: :internal, attributes: { "code.namespace" => "deliver_tree_contents_spokes!" }) do
      # Give Sinatra a chance to halt immediately if ETag matches.
      last_modified = calc_last_modified_for_object(current_repository)
      # Give Sinatra a chance to halt immediately if ETag matches.
      set_caching_headers!({ etag: content_metadata.root_tree_entry_oid, last_modified: last_modified })

      content_options = {
        repo: current_repository,
        ref: ref_name,
      }

      if medias.api_param?(:object)
        root_tree_entry = TreeEntry.new(
          current_repository,
          {
            "type" => "tree",
            "oid" => content_metadata.path_object_oid,
            "name" => File.basename(content_path),
            "path" => content_path,
          }
        )

        deliver :tree_object_content_hash, root_tree_entry, content_options.merge(tree_entries: spokes_tree_entries)
      else

        deliver :content_hash, spokes_tree_entries, content_options
      end
    end
  end

  # Fetch tree entries from spokes for the specified tree OID, adding submodule info if needed.
  sig { returns(T.nilable(T::Array[TreeEntry])) }
  def spokes_tree_entries
    return nil unless content_metadata.tree?

    entries = Repositories.domain.contents.tree_entries_by_metadata(
      repository: current_repository,
      metadata: content_metadata,
      path: normalized_path
    )

    entries&.map do |entry|
      TreeEntry.new(
        current_repository,
        {
          "type" => entry.type == :submodule ? "commit" : entry.type.to_s,
          "oid" => entry.oid,
          "path" => entry.path,
          "name" => entry.name,
          "mode" => entry.mode,
          "size" => entry.size,
          "collection" => true,
          "symlink_target" => entry.symlink_target&.oid,
          "symlink_target_object" => entry.symlink_target && {
            "type" => entry.symlink_target&.type == :submodule ? "commit" : entry.symlink_target&.type.to_s,
            "mode" => entry.symlink_target&.mode,
          }
        }
      ).tap do |tree_entry|
        tree_entry.path_prefix = normalized_path
        if tree_entry.submodule?
          tree_entry.submodule = Submodule.new(
            superproject_repository: current_repository,
            superproject_commit_oid: content_metadata.ref_commit_oid,
            submodule_data: {
              "path" => entry.submodule_path,
              "url" => entry.submodule_url,
              "name" => entry.submodule_name
            },
          )
        end
      end
    end
  end

  def submodule_tree_entry
    @submodule_tree_entry = if submodule_content.nil?
      nil
    else
      tree_entry_from_submodule(submodule: submodule_content)
    end
  end

  def submodule_content
    return @submodule_content if defined?(@submodule_content)
    return @submodule_content = nil unless content_metadata.submodule?

    submodules = Repositories.domain.contents.submodules_by_commit_and_paths(
      repository: current_repository,
      commit_oid: content_metadata.ref_commit_oid,
      paths: [normalized_path],
    )

    @submodule_content = submodules.any? ? submodules.first : nil
  end


  sig { params(submodule: Repositories::Contents::Submodule).returns(TreeEntry) }
  def tree_entry_from_submodule(submodule:)
    tree_entry = TreeEntry.new(
      current_repository,
      submodule_tree_entry_data_hash(submodule:),
    )

    tree_entry.submodule = Submodule.new(
      superproject_repository: current_repository,
      superproject_commit_oid: content_metadata.ref_commit_oid,
      submodule_data: {
        "path" => submodule.path,
        "url" => submodule.url,
        "name" => submodule.name
      },
    )

    tree_entry
  end

  sig { params(submodule: Repositories::Contents::Submodule).returns(T::Hash[String, T.untyped]) }
  def submodule_tree_entry_data_hash(submodule:)
    {
      "type" => "commit",
      "oid"  => submodule.oid,
      "mode" => 0o160000,
      "name" => submodule.name,
      "path" => submodule.path,
      "size" => nil,
      "content" => nil,
    }
  end

  def normalized_path
    return @normalized_path if defined?(@normalized_path)

    @normalized_path = GitRPC::Util.normalize_path(path_string)
  end

  def ref_name
    @ref_name ||= (params[:ref].presence || current_repository.default_branch).try(:b)
  end

  class ContentsAPIExperimentResponse
    attr_reader :status, :etag, :last_modified, :location
    attr_accessor :body

    def initialize(status:, body:, etag: nil, last_modified: nil, location: nil)
      @status = status
      @body = body
      @etag = etag
      @last_modified = last_modified
      @location = location
    end

    def ==(other)
      status == other.status &&
        body == other.body &&
        etag == other.etag &&
        last_modified == other.last_modified &&
        location == other.location
    end

    def to_h
      {
        status: status,
        location: location,
        etag: etag,
        last_modified: last_modified,
        body: body
      }.compact
    end
  end

  def serialize_body_for_experiment(serialize_method, object, options)
    options ||= {}
    options.update(default_options)

    options[:current_user] ||= @current_user

    return object if serialize_method == :raw

    serializer_options = Api::SerializerOptions.fill(options)

    serialized_object = Api::Serializer.serialize(serialize_method, object, serializer_options)

    if should_remove_links_from_response?(serialized_object)
      serialized_object = remove_links_from_response(serialized_object)
    end

    if user_agent.cli? || user_agent.browser?
      return GitHub::JSON.encode(serialized_object, pretty: true) + "\n"
    end

    GitHub::JSON.encode(serialized_object)
  end

  def remove_links_from_response(serialized_object)
    if serialized_object.is_a?(Array)
      return serialized_object.map { |item| remove_links_from_response(item) }
    end

    if serialized_object.is_a?(Hash)
      if serialized_object.key?(:entries)
        serialized_object[:entries] = serialized_object[:entries].map do |entry|
          remove_links_from_response(entry)
        end
      end

      return serialized_object.except(:_links, :download_url)
    end

    serialized_object
  end

  def should_remove_links_from_response?(serialized_object)
    if serialized_object.is_a?(Array)
      return serialized_object.any? { |item| should_remove_links_from_response?(item) }
    end

    if serialized_object.is_a?(Hash)
      if serialized_object.key?(:entries)
        return true if serialized_object[:entries].any? { |entry| should_remove_links_from_response?(entry) }
      end

      data = serialized_object.slice(:_links, :download_url)
      return false if data.blank?
      return true if data[:download_url]&.include?("token=")
      data[:_links]&.each do |_, value|
        return true if value&.include?("token=")
      end
    end

    false
  end

  sig { params(request: Sinatra::Request, enable_reverse_proxy: T::Boolean).returns(T.untyped) }
  def query_reposd(request:, enable_reverse_proxy: false)
    # The api router will rewrite the request path to the repositories/:id form
    # We need to use the original /repos/:owner/:repo/ path if that's what was given.
    request_path = request.path
    if original_nwo = request.env[GitHub::Routers::Api::ThisRepositoryNameWithOwnerKey]
      request_path = request.path.sub(/\/repositories\/\d*\//, "/repos/#{original_nwo}/")
    end

    escaped_request_path = encode_request_path(request_path)

    reposd_client.api_request(path: escaped_request_path, params: request.GET, headers: request.env, method: request.request_method, enable_reverse_proxy:)
  end

  # If the request path we're going to call reposd with contains invalid characters...
  # Temporarily remove the query string (if it exists)
  # Encode each segment of the path separately, leaving / characters intact
  # Encode query string where necessary
  # Join the path back together and reattach the query string
  def encode_request_path(request_path)
    begin
      URI.parse(request_path)
      request_path
    rescue URI::InvalidURIError
      if request_path =~ /(.*?\/contents)(.*)/
        api_url = $1
        path = $2
        if path != ""
          path, query = path.split("?", 2)
          path = CGI.unescape(path)
          pieces = path.split("/")
          pieces.map! { |part| CGI.escape(part) }
          path = pieces.join("/")
          if query
            query = query.gsub(/([^&=]+)/) { |part| CGI.escape(part) }
            path += "?#{query}"
          end
        end
        "#{api_url}#{path}"
      else
        request_path
      end
    end
  end

  sig { returns Repositories::ReposdClient }
  def reposd_client
    @reposd_client ||= Repositories::ReposdClient.new
  end

  VALID_DOC_URLS = [
    "https://docs.github.com/rest",
    "https://docs.github.com/rest/repos/contents#get-repository-content",
  ]

  sig { params(body: T.nilable(String), headers: T::Hash[String, T.untyped], hash_content: T::Boolean).returns(T.untyped) }
  def clean_response_body(body, headers, hash_content: false)
    return unless body.present?

    # It's possible to request a raw tree listing but we just return JSON so we still need to sanitize
    requested_raw = T.unsafe(self).medias.api_param?(:raw)
    content_type = headers["content-type"].presence || headers["Content-Type"]
    returning_raw = content_type&.include?("raw")

    return Digest::SHA256.hexdigest(body) if (requested_raw && returning_raw) && hash_content

    return body unless (headers["Content-Type"]&.include?("json") || headers["content-type"]&.include?("json")) && (body.include?("?token=") || hash_content)

    parsed_resp = JSON.parse(body, symbolize_names: true)

    parsed_resp = if parsed_resp.is_a?(Array)
      parsed_resp.map do |item|
        item = item.except(:_links, :download_url)
        item = hash_body_content(item) if hash_content
        item
      end
    else
      if parsed_resp.key?(:entries)
        parsed_resp[:entries] = parsed_resp[:entries].map do |entry|
          entry = entry.except(:_links, :download_url)
          entry = hash_body_content(entry) if hash_content
          entry
        end
      end

      clean_resp = parsed_resp.except(:_links, :download_url)

      if clean_resp.key?(:documentation_url) && VALID_DOC_URLS.include?(clean_resp[:documentation_url])
        clean_resp[:documentation_url] = "REDACTED"
      end

      clean_resp = hash_body_content(clean_resp) if hash_content
      clean_resp
    end

    json_encode_response_body(parsed_resp)
  rescue # rubocop:disable Lint/RescueException
    # Ignore any errors that occur when trying to parse the response body
    body
  end

  def json_encode_response_body(body)
    if user_agent.cli? || user_agent.browser?
      GitHub::JSON.encode(body, pretty: true) + "\n"
    else
      GitHub::JSON.encode(body)
    end
  rescue
    body
  end

  def hash_body_content(item)
    return item unless item.is_a?(Hash) && item.key?(:content)
    item[:content] = Digest::SHA256.hexdigest(item[:content])
    item
  end

  def transform_headers(headers)
    headers.transform_keys! { |key| key.downcase }

    if headers.key?("github-authentication-token-expiration")
      headers.delete("github-authentication-token-expiration")
      headers["github-authentication-token-expiration"] = "REDACTED"
    end

    if headers.key?("x-accepted-oauth-scopes")
      if ["repo", ""].include?(headers["x-accepted-oauth-scopes"])
        headers.delete("x-accepted-oauth-scopes")
        headers["x-accepted-oauth-scopes"] = "REDACTED"
      end
    end

    if FeatureFlag.vexi.enabled?(:ignore_accepted_perms_mismatch, default: false) && !headers.key?("x-accepted-github-permissions") && should_send_valid_permissions? && @operation.nil?
      headers["x-accepted-github-permissions"] = "contents=read"
    end

    if headers.key?("x-github-media-type")
      media_type = headers["x-github-media-type"]
      headers.delete("x-github-media-type")
      headers["x-github-media-type"] = media_type&.downcase
    end

    if headers.key?("x-github-sso")
      sso_header = headers["x-github-sso"]
      if sso_header&.starts_with?("required; url=")
        headers.delete("x-github-sso")
        headers["x-github-sso"] = sso_header.gsub(/(authorization_request=).*/, '\1REDACTED')
      end
    end

    headers
  end

  memoize def reposd_contents_experiment_enabled?
    @current_repository&.feature_flag_enabled?(:reposd_contents_experiment, default: false) || FeatureFlag.vexi.enabled?(:reposd_contents_experiment, default: false)
  end

  memoize def reposd_reverse_proxy_experiment_enabled?
    @current_repository&.feature_flag_enabled?(:reposd_reverse_proxy_experiment, default: false) || FeatureFlag.vexi.enabled?(:reposd_reverse_proxy_experiment, default: false)
  end

  memoize def should_publish_experiment_response?
    @current_repository&.feature_flag_enabled?(:repos_contents_hydro_publish, default: false) ||
      (@current_repository.nil? && FeatureFlag.vexi.enabled?(:repos_contents_hydro_publish, default: false)) ||
        request.get_header("HTTP_X_GITHUB_MIRRORED_REQUEST") == "1" ||
        reposd_contents_experiment_enabled?
  end

  def contents_request_rate_limited?(body)
    parsed_resp = JSON.parse(body, symbolize_names: true)

    return true if parsed_resp.is_a?(Hash) && parsed_resp[:status] == "403" && parsed_resp[:message].include?("rate limit exceeded")

    false
  rescue # rubocop:disable Lint/RescueException
    # Ignore any errors that occur when trying to parse the response body
    false
  end
end
