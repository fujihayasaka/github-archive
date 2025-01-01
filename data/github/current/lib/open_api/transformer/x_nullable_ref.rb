# typed: true
# frozen_string_literal: true

class OpenApi::Transformer::XNullableRef < OpenApi::Transformer
  def call(filename, content)
    return unless content.has_key?("x-nullable-ref")

    enabled = content["x-nullable-ref"]
    content.delete("x-nullable-ref")

    if enabled
      if content.has_key?("$ref")
        #repackage the whole thing as a anyOf
        content["anyOf"] = [
          { "type" => "null" },
          { "$ref" => "#{content["$ref"]}" }
        ]

        content.delete("$ref")
      else
        # TODO - emit a warning that we found a `x-nullable-ref: true` without an associated ref
      end
    end

    content
  end
end
