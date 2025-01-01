# typed: true
# frozen_string_literal: true

module Api::App::RepositoryContentHelpers
  extend T::Helpers

  include Scientist

  requires_ancestor { Api::App }
  requires_ancestor { Api::App::ContentHelpers }

  def serve_contents_with_spokes!(&block)
    GitHub.tracer.in_span("api.app.repository-content-helpers", kind: :internal, attributes: {
      "code.namespace" => "serve_contents_with_spokes"
    }) do |_span|

      # handle paths that end in /
      redirect(api_url(request.path[0..-2])) if content_path.ends_with?("/")

      if use_spokesd?
        if content_metadata.empty_repository?
          deliver_error!(404,
            message: "This repository is empty.",
            documentation_url: "/v3/repos/contents/#get-contents")
        elsif content_metadata.commit_not_found?
          deliver_error!(404,
            message: "No commit found for the ref #{tree_name}",
            documentation_url: "/v3/repos/contents/")
        elsif content_metadata.tree_not_found?
          deliver_error!(404,
            message: "No commit found for the ref #{tree_name}",
            documentation_url: "/v3/repos/contents/")
        elsif content_metadata.object_not_found?
          deliver_error!(404,
            message: "No object found for the path #{path_string}",
            documentation_url: "/v3/repos/contents/")
        end

        # Prevent from calling GitRPC when we call:
        # - Api::App::ContentHelpers#empty_repository?
        # - Api::App::ContentHelpers#commit_sha
        # - Api::App::ContentHelpers#tree_sha
        @empty_repository = false
        @commit_sha = content_metadata.ref_commit_oid
        @tree_sha = content_metadata.root_tree_entry_oid

        # Prevent from calling GitRPC when Api::App::ContentHelpers#tree method is called
        @tree = nil unless content_metadata.tree?
        # Prevent from calling GitRPC when Api::App::ContentHelpers#submodule method is called
        @submodule = nil unless content_metadata.submodule?
      end

      result = serve_contents(&block)

      compare_metadata

      result
    end
  end

  def use_spokesd?
    # GitHub.spokesd_enabled? returns true in production
    # However, in test, some tests are not ready to use spokesd yet
    # https://github.com/github/git-platform/issues/159
    GitHub.spokesd_enabled? && current_repository.feature_enabled?(:resolve_object_metadata_with_spokes)
  end

  def tree?
    # when FF is off, we need to call the #tree method to keep the old behavior
    return !tree.nil? unless use_spokesd?

    content_metadata.tree?
  end

  def submodule?
    # when FF is off, we need to call the #submodule method to keep the old behavior
    return !submodule.nil? unless use_spokesd?

    content_metadata.submodule?
  end

  def content_metadata
    return @content_metadata if defined?(@content_metadata)

    @content_metadata = Repositories.domain.contents.metadata_by_ref_and_path(
      repository: current_repository,
      ref: params[:ref],
      path: path_string,
    )

    @content_metadata
  end

  def compare_metadata
    return if current_repository.feature_enabled?(:resolve_object_metadata_with_spokes)

    science "resolve_object_metadata_with_spokes" do |e|
      e.run_if { GitHub.spokesd_enabled? }
      e.context({
        name_with_owner: current_repository.name_with_display_owner,
        ref: params[:ref],
        path: path_string
      })
      e.use do
        control_metadata_hash
      end
      e.try do
        candidate_metadata_hash
      end
    end

    nil
  end

  def control_metadata_hash
    return @control_metadata_hash if defined?(@control_metadata_hash)

    if empty_repository?
      @control_metadata_hash = {
        empty: true,
        commit_sha: nil,
        type: nil,
        tree_sha: nil,
        object_oid: nil
      }
    elsif tree
      @control_metadata_hash = {
        empty: false,
        commit_sha: commit_sha,
        type: :tree,
        tree_sha: tree_sha,
        object_oid: tree_object(tree).oid
      }
    elsif submodule
      @control_metadata_hash = {
        empty: false,
        commit_sha: commit_sha,
        type: :submodule,
        tree_sha: tree_sha,
        object_oid: submodule.oid
      }
    elsif blob
      @control_metadata_hash = {
        empty: false,
        commit_sha: commit_sha,
        type: :blob,
        tree_sha: tree_sha,
        object_oid: blob.oid
      }
    else
      @control_metadata_hash = {}
    end

    @control_metadata_hash
  end

  def candidate_metadata_hash
    {
      empty: content_metadata.empty_repository?,
      commit_sha: content_metadata.ref_commit_oid,
      type: content_metadata.path_object_type,
      tree_sha: content_metadata.root_tree_entry_oid,
      object_oid: content_metadata.path_object_oid
    }
  end

end
