# frozen_string_literal: true

class IconComponent < ApplicationComponent
  attr_reader :icon, :size, :args

  def initialize(icon:, size: :small, **args)
    @icon = icon
    @size = size
    @args = args
  end

  def call
    if svg_available?
      render_svg
    else
      render_octicon
    end
  end

  private

  # The invline_svg gem has the concept of an "asset file" that's responsible
  # for mapping an incoming string (icon name) to its corresponding SVG file.
  # We're using inline_svg's default implementation but rescuing the not-found
  # case so we can still fall back to rendering a matching Octicon.
  def svg_available?
    InlineSvg.configuration.asset_file.named(svg_path) ? true : false
  rescue InlineSvg::AssetFile::FileNotFound
    false
  end

  def render_svg
    inline_svg_tag svg_path, template: render_octicon(icon: TemplateTransform::TEMPLATE_ICON)
  end

  def svg_path
    "icons/#{icon}-#{size}.svg"
  end

  def render_octicon(icon: self.icon)
    render Primer::Beta::Octicon.new(icon: icon, size: size, **args)
  end
end
