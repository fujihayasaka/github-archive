# typed: true
# frozen_string_literal: true

class GitHub::SourceRenderedToggleComponent < ApplicationComponent
  def initialize(toggleable: true, source_selected: false, source_url: nil, rendered_url: nil, canonical_source_url: nil, canonical_rendered_url: nil)
    @toggleable = toggleable
    @source_selected = source_selected
    @source_url = source_url
    @rendered_url = rendered_url
    @canonical_source_url = canonical_source_url
    @canonical_rendered_url = canonical_rendered_url
  end

  def source_classes
    "source tooltipped tooltipped tooltipped-n #{'selected' if @source_selected} #{'js-permalink-replaceable-link' if @canonical_source_url}"
  end

  def rendered_classes
    "rendered tooltipped tooltipped tooltipped-n #{'selected' unless @source_selected} #{'js-permalink-replaceable-link' if @canonical_rendered_url}"
  end
end
