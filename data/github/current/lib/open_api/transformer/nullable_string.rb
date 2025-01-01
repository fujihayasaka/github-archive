# typed: true
# frozen_string_literal: true

class OpenApi::Transformer::NullableString < OpenApi::Transformer
  def call(filename, content)
    return unless content.has_key?("type") && content.has_key?("nullable") &&
      content["type"] == "string" && content["nullable"] == true

    content.delete("nullable")

    content["type"] = Array(content["type"]) << "null"

    if content.has_key?("enum") && !content["enum"].index(nil)
      content["enum"] << nil
    end

    content
  end
end
