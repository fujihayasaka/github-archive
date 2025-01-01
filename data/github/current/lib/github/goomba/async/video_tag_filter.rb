# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async

  # Processes video upload references generated in GitHub::Goomba::VideoTagFilter,
  # replacing the tags with an embedded video player when necessary.
  #
  # Read the documentation of GitHub::Goomba::VideoTagFilter first to note
  # how plain text and link target references are generated.
  #
  # Given the following tag:
  #
  #   <p gh:video-upload='{"src":"https://user-images.githubusercontent.com/7559041/1234.mp4"}'>
  #    <a href="https://user-images.githubusercontent.com/7559041/1234.mp4">https://user-images.githubusercontent.com/7559041/1234.mp4</a>
  #   </p>
  #
  # Finds the associated UserAsset from the `src`, and, if it is a valid video asset,
  # inserts a video tag.
  #
  #
  # Given the following tag:
  #
  #   <video
  #     gh:video-upload='{"src":"https://user-images.githubusercontent.com/7559041/1234.mp4"}'
  #     src="https://user-images.githubusercontent.com/7559041/1234.mp4"><video>
  #
  # Finds the associated UserAsset from the `src`. Like the links above, if it is
  # a valid video asset, adds the correct video attributes to the tag. Else, it
  # scrubs the video tag.
  class VideoTagFilter < NodeFilter
    include GitHub::Goomba::Reference::Helpers
    SELECTOR = Goomba::Selector.new(match: "video[gh|video-upload], p[gh|video-upload]")
    MARKDOWN_SELECTOR = Goomba::Selector.new(match: "p[gh|video-upload]")
    VIDEO_SELECTOR = Goomba::Selector.new(match: "video[gh|video-upload]")

    def initialize(*args)
      super
      @video_cache = {}
    end

    def selector
      SELECTOR
    end

    def async_scan
      Promise.all(@nodes.map do |node|
        next unless data = JSON.parse(node["gh:video-upload"])
        next unless video_url = data["src"]
        next unless guid = user_asset_guid(video_url)

        Platform::Loaders::UserAsset.load(guid).then do |asset|
          next unless asset&.video_content?

          Promise.all([asset.async_uploader, asset.async_repository])
            .then { @video_cache[video_url] = asset }
        end
      end)
    end

    def call(node)
      if node =~ MARKDOWN_SELECTOR
        call_p(node)
      elsif node =~ VIDEO_SELECTOR
        call_video(node)
      end
    end

    private

    def call_p(node)
      data = JSON.parse(node["gh:video-upload"])
      src = data["src"]
      node.remove_attribute("gh:video-upload")

      link_node = node.children.first
      valid_node =
        video_output_enabled_for_blob_user? &&
        is_element_node?(link_node) &&
        link_node["href"].to_s == src

      return nil unless valid_node

      video_ref = @video_cache[src]

      return nil unless video_ref

      wrap_video_player(video_ref, src)
    end

    def call_video(node)
      data = JSON.parse(node["gh:video-upload"])
      src = data["src"]
      video_src = node["src"]

      node.remove_attribute("gh:video-upload")

      # Video tag must have both the gh:video-upload src and a video src
      return "" if video_src != src

      video_ref = @video_cache[src]

      return "" if !video_ref

      wrap_video_player(video_ref, src)
    end

    def video_player_for(video, src)
      video_src = video.source_url(actor: video.uploader)
      ApplicationController.render(
        partial: "filter_partials/video_player",
        # The protected_src is the displayed url that may or may not be authenticated.
        # The video_src points to the cdn for display by the browser.
        locals: { video_name: video.name, video_src: video_src, protected_src: src },
        formats: [:html]
      )
    end

    def video_output_enabled_for_blob_user?
      blob_context = if context.has_key?(:blob) && context[:blob].is_a?(TreeEntry)
        context[:blob]
      end

      # we only care about checking the repository feature flag if the context is a blob
      return true if blob_context.nil?

      blob_context.repository
    end

    def user_asset_guid(url)
      @guids ||= {}

      guid = @guids[url]
      return guid if guid

      uri = Addressable::URI.parse(url)

      # UserAsset urls include guid, and depending on environment, may include asset
      # id. So, we pull out the last 5 elements to ensure we've got just the guid.
      filename = uri.basename.chomp(uri.extname) # First, remove the extension if present
      guid = filename.split("-").last(5).join("-") # Then extract the guid
      @guids[url] = guid
      guid
    end

    def wrap_video_player(video_ref, src)
      video_player = video_player_for(video_ref, src)

      return secured_asset_reference_wrapper(video_ref) { video_player } if video_ref.repository

      # We just check for `upload_container_type` here because user assets for gists that were not created yet won't
      # have the `upload_container_id` column set
      return gist_secured_asset_reference_wrapper(video_ref) { video_player } if video_ref.upload_container_type == Gist.name

      if video_ref.upload_container_type != UserAsset::REPOSITORY_BLOB && container = video_ref.upload_container
        return memex_secured_asset_reference_wrapper(video_ref) { video_player } if container.is_a?(MemexProject)
        return saved_reply_secured_asset_reference_wrapper(video_ref) { video_player } if container.is_a?(User)
      end

      return ghes_secured_legacy_asset_reference_wrapper(video_ref) { video_player } if legacy_ghes_asset?(video_ref)

      video_player
    end

    def legacy_ghes_asset?(video_ref)
      GitHub.storage_cluster_enabled? && video_ref.repository.nil? && video_ref.upload_container.nil?
    end
  end
end
