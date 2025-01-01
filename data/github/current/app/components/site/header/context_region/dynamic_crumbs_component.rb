# typed: true
# frozen_string_literal: true

class Site::Header::ContextRegion::DynamicCrumbsComponent < Site::Header::ContextRegion::CrumbsComponent
  def crumb_attributes(item)
    attrs = super(item)
    attrs[:data] ||= {}
    attrs[:data][:target] = "context-region-crumb.linkElement"
    attrs
  end
end
