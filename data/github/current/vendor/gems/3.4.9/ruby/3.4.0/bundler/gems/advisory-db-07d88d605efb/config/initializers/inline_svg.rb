# frozen_string_literal: true

class TemplateTransform < InlineSvg::CustomTransformation
  TEMPLATE_ICON = "dot-fill"

  def transform(doc)
    with_svg(doc) do |svg|
      template_svg = Nokogiri::XML::Document.parse(value).at_css("svg")

      template_svg.attributes.each do |attribute, value|
        svg.set_attribute(attribute, value)
      end

      svg.remove_class("octicon-#{TEMPLATE_ICON}")
      svg.add_class("octicon-inline-svg")
    end
  end
end

InlineSvg.configure do |config|
  config.add_custom_transformation(
    attribute: :template,
    transform: TemplateTransform,
  )
end

module InlineSvgStripper
  extend ActiveSupport::Concern

  class_methods do
    # Remove leading and trailing whitespace from inline_svg_tag output.
    def generate_html_from(*)
      super.strip
    end
  end
end

InlineSvg::TransformPipeline.prepend(InlineSvgStripper)
