# typed: true
# frozen_string_literal: true

module Gists
  # Controls the gist blob view in app/views/gists/_blob.html.erb
  class BlobView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
    include EncodingSafeParameterizeHelper
    include BlobHelper

    attr_reader :gist, :blob, :short_path

    def snippet?
      blob.try(:snippet?)
    end

    def blob_name
      blob.display_name
    end

    # Encode any character classes that are invalid in paths
    def encoded_blob_name
      Addressable::URI.encode_component(blob.name, Addressable::URI::CharacterClasses::PATH)
    end

    # Show the file box header?
    def show_header?
      attributes.fetch :show_header, true
    end

    # False for now until we add support
    def embedded?
      attributes.fetch :embedded, false
    end

    # What revision are we showing this blob for?
    #
    # The revision is passed in to the view model when on
    # the revisions.  We default to the gist main sha
    # everywhere else.
    def revision
      attributes.fetch :revision, gist.sha
    end

    # Can a user update this task list?
    #
    # Returns false for:
    # - anonymous gists
    # - embedded gists
    # - gists that need render
    # - binary gists
    # - image gists
    # - gists the viewing user doesn't own
    #
    # Returns true for everthing else
    def updatable?
      return if gist.owner.nil? || snippet? || embedded? || use_render?
      # NOTE: We're still seeing API issues where image blobs can come back as non binary
      return if blob.binary? || blob.image?

      gist.ui_content_adminable_by?(current_user)
    end

    # Used in anchors, and the occasional id
    def anchor
      "file-#{encoding_safe_parameterize(blob_name)}"
    end

    # Used to prefix any line number links
    def named_anchor_prefix
      "#{anchor}-"
    end

    def icon_symbol
      if blob.image?
        "image"
      else
        "code-square"
      end
    end

    def show_source_toggle?
      @show_source_toggle ||= blob.render_file_type_for_display(:view) ? true : false
    end

    # Is the source, or rendered version displaying?
    def source_displayed?
      show_source_toggle? &&
      short_path &&
      short_path == blob_short_path(blob)
    end

    # Should we use render for this blob?
    #
    # Delegate to blob render file if we aren't using render
    # Otherwise toggle based on value of source_displayed?
    def use_render?
      return blob.render_file_type_for_display(:view) unless show_source_toggle?
      !source_displayed?
    end

    # Should the blob appear "rendered"? i.e. Using viewscreen to display .geojson file
    # as visual map. Even if the blob *can* be rendered, the user may have selected
    # the "source" view, in which case we should *not* `use_code_rendering_service?`.
    def display_with_code_rendering_service?
      if code_rendering_service&.supports_view?
        !source_displayed?
      else
        false
      end
    end

    def code_rendering_service
      return nil unless blob
      @code_rendering_service ||= CodeRenderingService.for(blob, :view, current_user)
    end

  end
end
