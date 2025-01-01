# typed: true
# frozen_string_literal: true

#
# Factory that builds view and diff classes which facilitate communication between dotcom and the Notebooks and
# Viewscreen rendering services. The logic in these classes constructs the iframe urls and manages how renderable
# files are displayed in rails views.
# It calls out to TreeEntryRenderHelper a lot, we may want to move that or rename it or something eventually?

module CodeRenderingService
  # Checks the view type and builds the viewscreen class
  # associated with it.
  # Params
  # blob: the blob of data that is associated with the files to show
  # view_type: the type of view that will be requested from viewscreen
  # current_user: the user that is requesting the viewscreen
  # current_repository: the repository that is being viewed
  def self.for(blob, view_type, current_user, current_repository = nil, diff: nil, opts: {})
    if [:view, :preview, :img, :image].include?(view_type)
      view = Viewscreen::ViewComponent.new(blob, view_type, current_user, current_repository, opts: opts)
      return view if view.supports_view?
      view = Notebook::ViewComponent.new(blob, view_type, current_user, current_repository, opts: opts)
      view
    elsif view_type == :diff
      raise ArgumentError, "diff must be provided for diff view" unless diff
      # We do more notebook traffic than image diff traffic, so we check for notebook first
      view = Notebook::DiffComponent.new(blob, view_type, current_user, current_repository, diff: diff, opts: opts)
      return view if view.supports_view?
      Viewscreen::DiffComponent.new(blob, view_type, current_user, current_repository, diff: diff, opts: opts)
    else
      CodeRenderingService::NullComponent.new
    end
  end

  def self.for_markdown(render_type, entity, view_data, opts: {})
    Viewscreen::MarkdownComponent.new(render_type: render_type, view_data: view_data, entity: entity, opts: opts)
  end

  def self.selector_list
    Viewscreen::MarkdownComponent.selector_list
  end

  def self.markdown_cache_key(context)
    GitHub::Goomba::CodeRenderingServiceFilter.cache_key(context)
  end

  def self.all_markdown_feature_flags
    Viewscreen::MarkdownComponent::FLAGGED_FEATURES.map do |render_type|
      "markdown-#{render_type}".to_sym
    end
  end
end
