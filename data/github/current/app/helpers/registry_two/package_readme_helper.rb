# typed: true
# frozen_string_literal: true

module RegistryTwo
  module PackageReadmeHelper
    include ActiveSupport::Concern

    ANNOTATION_SOURCE_COMMIT = "org.opencontainers.image.sourcecommit"
    ANNOTATION_CONTENT_PATH = "org.opencontainers.image.contentpath"
    NPM_NO_README = "ERROR: No README data found!"
    README_LAYER_MEDIA_TYPE = "application/vnd.oci.github.package.readme.v1.txt"
    # immutable actions used a different key for the source commit
    IA_VERSION_SOURCE_COMMIT = "com.github.source.commit"

    # retrieves the content of the readme for given package_version & repository
    # @should_get_default: for package landing page, we want to get the default readme if no readme is found
    # however for package version landing page, we want to get the readme only if it is found
    # and if it's not found, we want to return nil so that we display instructions on how to add description
    def package_readme(package_version: nil, repository: nil, should_get_default: false, namespace: nil, viewer_can_read_repo: false)
      ecosystem = package_version&.ecosystem&.downcase.to_sym

      # for npm (string)
      if ecosystem == :npm
        return package_version&.npmMetadata&.readme if package_version&.npmMetadata&.readme.present? && package_version&.npmMetadata&.readme != NPM_NO_README
      end

      # for container (TreeEntry)
      if ecosystem == :container
        # we will only attempt to read the readme if the user has read access to the repo
        if viewer_can_read_repo
          # if annotations are given for the readme, use them
          all_labels = package_version&.containerMetadata&.labels&.all_labels

          sourcecommit = all_labels && all_labels[ANNOTATION_SOURCE_COMMIT] ? all_labels[ANNOTATION_SOURCE_COMMIT] : all_labels[IA_VERSION_SOURCE_COMMIT]
          contentpath = all_labels && all_labels[ANNOTATION_CONTENT_PATH] ? all_labels[ANNOTATION_CONTENT_PATH] : "README.md"
          begin
            # given contentpath could be a file, so try to find a readme in that file
            # if it is a directory, this will raise an error
            # GitRPC::Failure: TypeError: entry_id must be either an index or a filename
            # GitRPC::InvalidObject: Invalid type at path: docs, expected blob, got tree
            # if commit is invalid, this will raise an error
            readme = repository&.blob(sourcecommit, contentpath) if sourcecommit && contentpath

          rescue GitRPC::Failure, GitRPC::Error
            # content path could be a directory, so try to find a readme in that directory
            contentpath = File.join(contentpath, "README.md") if contentpath
            # if commit is invalid, this will raise an error
            begin
              readme = repository&.blob(sourcecommit, contentpath) if sourcecommit && contentpath
            rescue GitRPC::Failure, GitRPC::Error
              readme = nil
            end
          end
          # return readme if found
          return readme if readme
        end

        # if there's a layer with README media type, use that
        layers = package_version.containerMetadata.manifest&.layers
        digest = layers&.find { |layer| layer.media_type == README_LAYER_MEDIA_TYPE }&.digest if layers
        readme = ContainerRegistry::Twirp.container_registry_client.get_blob(
          namespace: namespace,
          digest: digest
        ) if namespace && digest
        # return readme if found
        return readme if readme
      end

      # default behavior (TreeEntry)
      repository&.preferred_readme if should_get_default && viewer_can_read_repo
    end
  end
end
