# typed: true
# frozen_string_literal: true

class Actions::Resolver::V2::Internal::PackageResolver
  extend T::Sig

  InvalidActionPackageError = Class.new(StandardError)
  InvalidPackageVersionMetadataResponseError = Class.new(StandardError)

  def initialize(metric_namespace:, metric_tags:, actor_id:, actor_type:)
    @metric_namespace = metric_namespace
    @metric_tags = metric_tags
    @actor_id = actor_id
    @actor_type = actor_type
  end

  # The returned results are not guaranteed to be in the same order as the input actions.
  sig do
    params(actions: T::Array[Actions::Resolver::V2::Internal::ActionsCollection::PackageAction])
      .returns(T::Array[Actions::Resolver::Internal::ResolvedAction])
  end
  def resolve(actions:)
    GitHub.dogstats.time("#{@metric_namespace}.actions.package_resolver.resolve.time", tags: @metric_tags) do
      results = []

      actions_to_presign = []
      manifest_digests = []
      layer_digests = []

      # Get the digests for all actions (1 request for all actions).
      action_references = actions.map do |action|
        nwo_parts = action.resolved_nwo.split("/")
        {
          namespace: nwo_parts[0],
          name: nwo_parts[1],
          semver_ref: action.full_semver,
        }
      end
      resp = GitHub.dogstats.time("#{@metric_namespace}.actions.package_resolver.resolve.get_action_package_versions_metadata.time", tags: @metric_tags) do
        PackageRegistry::Twirp.action_packages_client.get_action_package_versions_metadata(action_references: action_references)
      end

      # This can't really happen unless there's a bug in the package registry.
      # We still check for it to document the assumption.
      # Unlike the network errors this one isn't rescued at the API handler level.
      unless actions.size == resp.results.size
        raise InvalidPackageVersionMetadataResponseError, "Number of returned action package versions metadata does not match number of actions nr_actions=#{actions.size} nr_metadata=#{resp.results.size}"
      end

      actions.zip(resp.results).each do |action, result|
        if !result.found

          GitHub.dogstats.increment(
            "#{@metric_namespace}.actions.resolve_action",
            tags: ["error:unknown_version"].concat(@metric_tags)
          )

          GitHub.logger.warn("Unable to resolve action due to unknown version",
            "code.namespace": "Actions::Resolver::V2::Internal::PackageResolver",
            "code.function": "resolve",
            "gh.action.requested_nwo": action.requested_nwo,
            "gh.action.processed_nwo": action.processed_nwo,
            "gh.action.ref": action.ref,
            "gh.action.normalised_semver": action.normalised_semver,
            "gh.action.full_semver": action.full_semver,
            "gh.action.package_id": action.package_id,
            "gh.action.package_visibility": action.package_visibility)

          results << Actions::Resolver::Internal::Error.new(
            requested_name: action.requested_nwo,
            ref: action.ref,
            msg: "Unable to resolve action `#{action.requested_nwo}@#{action.ref}`, unable to find version `#{action.ref}`")

          next
        end

        tar_layer = result.metadata.manifest.layers.find { |l| l.media_type == "application/vnd.github.actions.package.layer.v1.tar+gzip" }
        zip_layer = result.metadata.manifest.layers.find { |l| l.media_type == "application/vnd.github.actions.package.layer.v1.zip" }

        # This can't really happen unless there's a bug in the package registry or the upload process for action packages.
        # We still check for it to document the assumption.
        # Unlike the network errors this one isn't rescued at the API handler level.
        unless tar_layer && zip_layer
          raise InvalidActionPackageError, "Unable to find tar and zip layers for action package with requested_nwo=#{action.requested_nwo} resolved_nwo=#{action.resolved_nwo} ref=#{action.ref} full_semver=#{action.full_semver}"
        end

        # Store the digests for:
        # - The entire manifest
        # - The tar layer & the zip layer
        actions_to_presign << action
        manifest_digests << result.metadata.manifest.digest
        layer_digests << [tar_layer.digest, zip_layer.digest]
      end

      if actions_to_presign.size == 0
        return results
      end

      # Get pre-signed URLs for each not yet failed action (1 request for all actions)
      blob_identifiers = to_blob_identifiers(actions_to_presign, layer_digests)
      urls = GitHub.dogstats.time("#{@metric_namespace}.actions.package_resolver.resolve.generate_presigned_urls.time", tags: @metric_tags) do
        ContainerRegistry::Twirp.container_registry_client.generate_presigned_urls(
          actor_id: @actor_id,
          actor_type: @actor_type,
          blob_identifiers: blob_identifiers)
      end

      # Transform manifest digests
      # This is done to remove the `sha265:` prefix and add a new one to
      # easily differentiate between package SHAs and git SHAs.
      # The runner will display these SHAs in the log when downloading
      # an action and use them to cache the actions locally.
      manifest_digests.map! do |digest|
        digest.sub("sha256:", "package_")
      end

      GitHub.dogstats.increment(
        "#{@metric_namespace}.actions.resolve_action",
        tags: ["type:package"].concat(@metric_tags),
        by: actions.count
      )

      actions_to_presign.each do |action|
        manifest_digest = manifest_digests.shift
        tar_url = urls.shift
        zip_url = urls.shift

        results << Actions::Resolver::Internal::ResolvedAction.new(
          package_id: action.package_id,
          requested_name: action.requested_nwo,
          resolved_name: action.resolved_nwo,
          resolved_sha: manifest_digest,
          tar_url: tar_url,
          zip_url: zip_url,
          ref: action.ref,
          resolved_ref: action.full_semver,
          visibility: action.package_visibility)
      end

      results
    end
  end

  private

  def to_blob_identifiers(actions, digests)
    actions.map.with_index do |action, index|
      nwo_parts = action.resolved_nwo.split("/")
      tar_digest, zip_digest = digests[index]
      [
        { namespace: nwo_parts[0], name: nwo_parts[1], digest: tar_digest },
        { namespace: nwo_parts[0], name: nwo_parts[1], digest: zip_digest }
      ]
    end.flatten
  end
end
