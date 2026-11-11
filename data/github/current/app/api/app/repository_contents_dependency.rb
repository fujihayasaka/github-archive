# typed: true
# frozen_string_literal: true

module Api::App::RepositoryContentsDependency
  extend T::Helpers

  include Api::App::ContentHelpers

  requires_ancestor { Api::App }

  # Ensures the file is writable. Currently used to stop writes to a
  # repository's file if it's a sensitive file such as workflows/a.yml or
  # workflows-lab/ci.yml
  #
  # repo - Repository to check.
  # path - File to check access to.
  #
  # If access is denied to the file, halt the request.
  sig { params(repo: Repository, path: String, oid: T.any(String, T::Array[String])).void }
  def ensure_file_writable!(repo, path, oid)
    control_access :write_file,
      resource: repo,
      path: path,
      oid: oid,
      allow_integrations: true,
      allow_user_via_granular_actor: true
  end

  #
  # Helper method for serializing and delivering a tree to the client
  #
  sig { returns(T.untyped) }
  def deliver_tree_contents
    GitHub.tracer.in_span("api.app.repository-contents", kind: :internal, attributes: {
      "code.namespace" => "deliver_tree_contents"
    }) do |_span|
      last_modified = calc_last_modified_for_object(current_repository)

      # Give Sinatra a chance to halt immediately if ETag matches.
      set_caching_headers!({ etag: tree_sha, last_modified: last_modified })

      content_options = {
        repo: current_repository,
        ref: tree_name,
      }

      if medias.api_param?(:object)
        deliver :tree_object_content_hash, tree_object(tree), content_options
      else
        deliver :content_hash, tree, content_options
      end
    end
  end

  def deliver_submodule_contents
    GitHub.tracer.in_span("api.app.repository-contents", kind: :internal, attributes: {
      "code.namespace" => "deliver_submodule_contents"
    }) do |_span|
      last_modified = calc_last_modified_for_object(current_repository)

      # Give Sinatra a chance to halt immediately if ETag matches.
      set_caching_headers!({ etag: tree_sha, last_modified: last_modified })

      deliver :content_hash,
        submodule,
        repo: current_repository,
        full: true,
        ref: tree_name
    end
  end
end
