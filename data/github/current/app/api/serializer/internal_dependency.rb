# typed: false
# frozen_string_literal: true

module Api::Serializer::InternalDependency
  # uploadable - An ActiveRecord object with AssetUploadable included.
  # options    - Optional Hash.
  #              :origin - String Origin HTTP header value.
  def internal_asset_hash(uploadable, options = nil)
    options = Api::SerializerOptions.from(options)
    hash = {
      oid: uploadable.oid,
      size: uploadable.size,
      updated_at: time(uploadable.updated_at),
      etag: uploadable.etag,
      path_prefix: uploadable.alambic_path_prefix,
    }

    options = Api::SerializerOptions.from(options)

    if options[:user]
      hash[:user_id] = options[:user].id
    end

    if ctype = uploadable.try(:content_type)
      hash[:content_type] = ctype
    end

    if uploadable.respond_to?(:alambic_download_headers)
      hash[:headers] = uploadable.alambic_download_headers(options)
    end

    if filters = uploadable.try(:alambic_download_filters)
      hash[:filters] = filters
    end

    return hash if !(uploadable && asset = uploadable.asset)

    if asset.width.to_i + asset.height.to_i > 0
      hash.update(width: asset.width, height: asset.height)
    end

    hash
  end

  def internal_avatar_asset_hash(avatar, options = nil)
    internal_asset_hash(avatar, options).update \
      cropped_dimensions: avatar.cropped_dimensions,
      model_name: "avatar"
  end

  def internal_media_asset_hash(blob, options = nil)
    options = Api::SerializerOptions.from(options)
    repo = options[:repo]
    internal_asset_hash(blob, options).update(
      repository_owner_id: repo.owner_id,
      repository_id: repo.id,
      network_owner_id: blob.repository_network_owner_id,
      network_id: blob.repository_network_id,
      root_repository_id: blob.root_repository_id,
      responsible_owner_id: blob.responsible_owner_id,
      model_name: "media_blob",
    )
  end

  def internal_avatar_hash(avatar, options = nil)
    {
      id: avatar.id,
      cropped_dimensions: avatar.cropped_dimensions,
      width: avatar.width,
      height: avatar.height,
      url: avatar.url(nil, options[:current_user]),
      path_prefix: avatar.alambic_path_prefix,
    }
  end

  ## New storage stuff

  # Builds a JSON object that tells Alambic how to SAVE a file.
  #
  # uploadable - An ActiveRecord object with AssetUploadable included.
  # options    - Optional Hash.
  #              :origin - String Origin HTTP header value.
  #              :public_key - PublicKey the deploy key actor, or nil
  def internal_storage_validation_hash(uploadable, options = nil)
    options = Api::SerializerOptions.from(options)
    policy = uploadable.storage_policy(
      actor: options.current_user,
      repository: options.repo,
      key: options.public_key,
    )

    body = {
      replicas: [],
      verify_token: uploadable.storage_cluster_upload_token(policy, expires: 24.hours),
    }

    replicas = GitHub::Storage::Allocator.least_loaded_replicas
    Array(replicas[:hosts]).each do |host|
      body[:replicas] << { url: (GitHub.storage_replicate_fmt % host) }
    end
    Array(replicas[:non_voting]).each do |host|
      body[:replicas] << {
        url: (GitHub.storage_replicate_fmt % host),
        non_voting: true,
      }
    end

    if filters = uploadable.try(:alambic_upload_filters)
      body[:filters] = filters
    end

    blob = uploadable.storage_blob
    if blob && blob.oid.present?
      body[:oid] = blob.oid
      body[:path_prefix] = blob.storage_partition
    end

    body
  end

  # Builds a JSON object that tells Alambic how to deliver a file.
  #
  # uploadable - An ActiveRecord object with AssetUploadable included.
  # options    - Optional Hash.
  #              :origin - String Origin HTTP header value.
  def internal_storage_hash(uploadable, options = nil)
    options = Api::SerializerOptions.from(options)
    hash = {
      id: uploadable.id,
      href: uploadable.storage_external_url(options[:current_user]),
      content_type: uploadable.storage_download_content_type,
      oid: uploadable.oid,
      etag: uploadable.oid,
      size: uploadable.size,
      updated_at: time(uploadable.updated_at),
    }

    if GitHub.storage_cluster_enabled?
      blob = uploadable.storage_blob
      hash.update(
        path_prefix: blob.storage_partition,
        replicas: blob.fileservers(host: options[:env]["X_GITHUB_ALAMBIC_HOSTNAME"], datacenter: options[:env]["X_GITHUB_ALAMBIC_DATACENTER"]).map { |url| { url: url } },
      )

      if api_url = uploadable.storage_api_url
        hash[:api_url] = api_url
      end
    end

    options = Api::SerializerOptions.from(options)

    if options[:user]
      hash[:user_id] = options[:user].id
    end

    if uploadable.respond_to?(:alambic_download_headers)
      hash[:headers] = uploadable.alambic_download_headers(options)
    end

    if filters = uploadable.try(:alambic_download_filters)
      hash[:filters] = filters
    end

    hash
  end

  def internal_avatar_storage_hash(avatar, options = nil)
    internal_storage_hash(avatar, options).update \
      id: avatar.id,
      width: avatar.width,
      height: avatar.height,
      cropped_dimensions: avatar.cropped_dimensions,
      model_name: "avatar"
  end

  def internal_repository_hash(repository, options = nil)
    {
      repository_id: repository.id,
      name_with_owner: repository.name_with_owner_for_api(use: options[:serialize_login]),
      network_id: repository.network_id,
      owner_id: repository.owner_id,
      global_relay_id: repository.global_relay_id,
    }
  end

  def internal_gist_hash(gist, options = nil)
    {
      gist_id: gist.id,
      repo_name: gist.repo_name,
    }
  end

  def internal_git_push_output(content, options = nil)
    { output: content }
  end

  def internal_token_validation_output(valid, options)
    {
      page_id: options[:repo].page.id,
      repository_id: options[:repo].id,
      owner_id: options[:repo].owner.id,
      pages_auth: valid
    }
  end

  def internal_app_manifest_response(app, options)
    {
      global_relay_id: app.global_relay_id,
      fingerprint: app.synchronization_fingerprint,
      type: app.class.to_s,
      settings: ProximaAppRequest::AppManifest.new(app).serialize_manifest
    }
  end

  def internal_apps_privileges_manifest_hash(configuration, options)
    manifest = { "Integration" => [], "OauthApplication" => [] }.tap do |hash|
      configuration.each do |type, configurations_for_type|
        configurations_for_type.each do |app|
          config = app.deep_dup
          config[:id] = Apps::Privileged::Registry.app_id(app_alias: app[:alias], type: type)

          remove_procs(config[:capabilities])
          remove_procs(config[:properties])

          hash[type] << config
        end
      end
    end

    data = Base64.encode64(manifest.to_json)

    {
      data: data
    }
  end

  private

  def remove_procs(hash)
    hash.each do |key, value|
      if value.is_a?(Proc)
        hash[key] = :proc
      elsif value.is_a?(Hash)
        remove_procs(value)
      end
    end
  end
end
