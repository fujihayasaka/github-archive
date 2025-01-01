# typed: true
# frozen_string_literal: true

module CodeRenderingService
  # Base class for all viewscreen models
  # includes common methods for all viewscreens
  class BaseComponent < ApplicationComponent # rubocop:disable ViewComponent/ComponentsHaveUnitTests

    include CodeRenderingService::QueryParams

    attr_reader :blob, :view_type, :render_type, :opts
    attr_accessor :current_user, :current_repository

    MAX_NOTEBOOK_SIZE = 30.megabytes
    MAX_BLOB_SIZE = 250.megabytes

    sig do
      params(
        blob: TreeEntry,
        view_type: Symbol,
        current_user: T.nilable(User),
        current_repository: T.nilable(T.any(Repository, Gist, GitHub::Unsullied::Wiki)),
        opts: T::Hash[Symbol, T.untyped]
      )
      .void
    end
    def initialize(blob, view_type, current_user, current_repository = nil, opts: {})
      @blob = blob
      @view_type = view_type
      @current_user = current_user
      @current_repository = current_repository
      @opts = opts
      set_render_type
    end

    sig { returns(T.nilable(T::Boolean)) }
    def supports_view?
      supported_views.keys.include?(@render_type) &&
      supported_views[render_type].include?(@view_type) &&
      enabled_for_user?(@render_type)
    end

    sig { returns(T::Boolean) }
    def is_notebook?
      @render_type == :ipynb
    end

    def supported_views
      raise NotImplementedError
    end

    def flagged_features
      raise NotImplementedError
    end

    def host_url
      raise NotImplementedError
    end

    def iframe_url
      raise NotImplementedError
    end

    memoize def identity
      SecureRandom.uuid
    end

    sig { returns(T::Boolean) }
    def too_big_to_display?
      blob && render_type == :ipynb ? blob.size > MAX_NOTEBOOK_SIZE : blob && blob.size > MAX_BLOB_SIZE
    end

    sig { returns(String) }
    def state_class
      iframe_url.nil? ? "is-render-failed-fatal" : "is-render-pending"
    end

    private

    sig { params(render_type: Symbol).returns(T::Boolean) }
    def enabled_for_user?(render_type)
      return true unless flagged_features.include?(render_type)
      flag = "#{self.class.module_parent.to_s.downcase}-#{render_type}".to_sym
      GitHub.flipper[flag].enabled?(current_user)
    end

    # Internal: Detect render file type for tree entry file.
    #
    # Returns symbol file type or nil.
    sig { returns(T.nilable(Symbol)) }
    def set_render_type
      if blob.symlink?
        return @render_type = nil
      end

      @render_type = case
      when TreeEntryRenderHelper.solid?(blob) then :solid
      when TreeEntryRenderHelper.pdf?(blob) then :pdf
      when TreeEntryRenderHelper.topojson?(blob) then :topojson
      when TreeEntryRenderHelper.geojson?(blob) then :geojson
      when TreeEntryRenderHelper.svg?(blob) then :svg
      when TreeEntryRenderHelper.img?(blob) then :img
      when TreeEntryRenderHelper.psd?(blob) then :psd
      when TreeEntryRenderHelper.ipynb?(blob) then :ipynb
      when TreeEntryRenderHelper.mermaid?(blob) then :mermaid
      else nil
      end

      if @render_type && GitHub.render_type_filter.any?
        # If filters are set, require type to be allowed
        # Primarily used for Enterprise where some formats are disabled
        unless GitHub.render_type_filter.include?(@render_type.to_s)
          @render_type = nil
        end
      end

      @render_type
    end

    sig do
      params(
        repo: T.any(Repository, Gist),
        path: String,
        sha: String,
        lfs_pointer: T.nilable(Media::Pointer)
      )
      .returns(String)
    end
    def generate_codeload_url(repo, path, sha, lfs_pointer)
      if lfs_pointer && repo.is_a?(Repository)
        TreeEntryRenderHelper.lfs_blob_url(current_user, repo, sha, path, lfs_pointer.oid)
      elsif repo.is_a?(Gist)
        TreeEntryRenderHelper.raw_gist_url(current_user, repo, sha, path)
      else
        TreeEntryRenderHelper.raw_blob_url(current_user, repo, sha, Array(path).join("/"), expires_key: :render, host: GitHub.render_raw_host_name)
      end
    end

    # Encode the URL as a hex string to never have to worry about
    # any character encoding not matching what we can send in URL
    #
    # Returns a String
    sig { params(url: String).returns(String) }
    def encode_url(url)
      url.to_s.unpack1("H*")
    end

  end # class ::Base
end
