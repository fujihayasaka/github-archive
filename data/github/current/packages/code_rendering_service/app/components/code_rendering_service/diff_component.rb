# typed: true
# frozen_string_literal: true
require_relative "../code_rendering_service/base_component"
require "active_support/core_ext/numeric"
module CodeRenderingService
  # A viewscreen diff is a rendered version of a file in the diff view
  class DiffComponent < CodeRenderingService::BaseComponent
    attr_reader :diff

    sig do
      params(
        blob: TreeEntry,
        view_type: Symbol,
        current_user: T.nilable(User),
        current_repository: T.nilable(T.any(Repository, Gist, GitHub::Unsullied::Wiki)),
        diff: T.nilable(GitHub::Diff::Entry),
        opts: T::Hash[Symbol, T.untyped]
      )
      .void
    end
    def initialize(blob, view_type, current_user, current_repository = nil, diff: nil, opts: {})
      @diff = diff
      super(blob, view_type, current_user, current_repository, opts: opts)
    end

    ## Sets up the iframe url for a template using the current context of the view.
    sig { returns(URI::Generic) }
    def iframe_url
      @url ||= rich_diff_url(
        file_view: content[:view],
        file_list_view: content[:file_list_view],
      )
    end

    # Constructs a render diff url
    # This is used to create the url for the iframe based on the param options passed in:
    # diff - GitHub::Diff::Entry object to be rendered, contains two paths to two versions of a file
    # file_view (Optional) - Diff::FileView the current file being rendered by the template
    # file_list_view (Optional) - Diff::FileListView The list of Diff::FileView to be rendered in the
    #                             current template being rendered
    # Returns - String url to use when passing the encoded urls for the codeload resources to be rendered
    #           by the code rendering service
    #      Get Params:
    #         color_mode: The users selected color mode
    #         enc_url1: The hash encoded url to the original verision of the file being diffed
    #         enc_url2: The hash encoded url to the newer verision of the file being diffed
    #         size1: Size of blob 1 from enc_url1
    #         size2: Size of blob 2 from enc_url2
    #         path: file path to the blob
    #         repository_id: database id of the repository
    #         commit: the commit sha of the latest change
    #         nwo: Repository Name with owner
    #         repository_type: Gist or Repository
    sig do
      params(
        file_view: T.nilable(Diff::FileView),
        file_list_view: T.nilable(Diff::FileListView)
      )
      .returns(URI::Generic)
    end
    def rich_diff_url(file_view:, file_list_view:)
      url1, url2 = raw_diff_urls(diff)

      # Added diffs are special cased to avoid processing
      # a diff against nothing.
      if diff.added?
        extra = {
          repository_id: current_repository.try(:id),

          # Added only has b_*, since they are treated by
          # render as /view/ requests
          path: diff.b_path,
          commit: diff.b_sha,
          color_mode: color_mode,
        }
        return rich_added_url(T.must(url2), extra: extra)
      end

      params = {}
      params[:color_mode] = color_mode
      params[:enc_url1] = encode_url(url1) if url1
      params[:enc_url2] = encode_url(url2) if url2
      if file_view && file_list_view && diff.binary?
        file_view.set_diff_blob_sizes(file_list_view)
        size1 = file_view.diff_base_blob_size
        size2 = file_view.diff_head_blob_size
        if !size1.zero? || !size2.zero?
          params[:size1] = size1
          params[:size2] = size2
        end
      end

      params[:repository_id] = current_repository.try(:id)
      params[:nwo] = current_repository.try(:nwo)
      params[:repository_type] = current_repository.class.try(:name)

      params[:path] = diff.a_path
      params[:commit] = diff.a_sha
      params[:logged_in] = logged_in?

      params.merge(useragent_to_h)

      if bypass_fastly?(blob.repository)
        params[:bypass_fastly] = true
      end

      query = params.to_param
      path = "/diff/#{render_type}"

      URI.parse("#{host_url}#{path}?#{query}")
    end

    # Whether the view is toggalable to a syntax view/rich view
    sig { returns(T.nilable(T::Boolean)) }
    def rich_view_toggleable?
      supports_view?
    end

    sig { returns(T.nilable(T::Boolean)) }
    def default_to_rich_diff_view?
      supports_view?
    end

    sig { returns(T.nilable(T::Boolean)) }
    def supports_view?
      return false if diff.deleted?
      super
    end

    private

    sig { params(url: String, extra: T::Hash[Symbol, T.untyped]).returns(URI::Generic) }
    def rich_added_url(url, extra: {})
      params = extra.merge({ enc_url: encode_url(url) }).to_param
      path = "/added/#{render_type}"
      URI.parse("#{host_url}#{path}?#{params}")
    end

    sig { params(diff: GitHub::Diff::Entry).returns(T::Array[T.nilable(String)]) }
    def raw_diff_urls(diff)
      pointer1, pointer2 = Media::Blob.pointers_from_diff(diff)

      [
        raw_diff_base_blob_url(diff, pointer1),
        raw_diff_head_blob_url(diff, pointer2),
      ]
    end

    sig { params(diff: GitHub::Diff::Entry, pointer: T.nilable(Media::Pointer)).returns(T.nilable(String)) }
    def raw_diff_base_blob_url(diff, pointer = nil)
      return unless diff.a_path && diff.a_sha
      generate_codeload_url(current_repository, diff.a_path, diff.a_sha, pointer)
    end

    sig { params(diff: GitHub::Diff::Entry, pointer: T.nilable(Media::Pointer)).returns(T.nilable(String)) }
    def raw_diff_head_blob_url(diff, pointer = nil)
      return unless diff.b_path && diff.b_sha
      generate_codeload_url(current_repository, diff.b_path, diff.b_sha, pointer)
    end
  end
end
