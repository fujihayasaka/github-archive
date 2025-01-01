# typed: true
# frozen_string_literal: true

class StructuredTemplateWithMetadata
  attr_accessor :structured_body

  def initialize(structured_body)
    @structured_body = structured_body.to_h
  end

  def to_s
    rendered_body + metadata_string
  end

  private

  def metadata_string
    "\n\n<!-- #{TemplatableContent::METADATA_KEY} = #{structured_body.to_json} -->"
  end

  def rendered_body
    structured_body.map do |id, response|
      next if id.start_with?("label.") || id == TemplatableContent::TEMPLATE_PATH_KEY

      label = structured_body["label.#{id}"] || id
      "### #{label}\n\n#{response}"
    end.compact.join("\n\n")
  end
end
