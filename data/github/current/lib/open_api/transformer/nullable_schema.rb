# typed: true
# frozen_string_literal: true

class OpenApi::Transformer::NullableSchema < OpenApi::Transformer
  def call(filename, content)
    return unless content.has_key?("nullable") && content["nullable"] == true

    content.delete("nullable")

    content["type"] = Array(content["type"])
    content["type"] << "null"

    content
  end
end
