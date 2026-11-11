# typed: true
# frozen_string_literal: true

class OpenApi::Transformer::Example < OpenApi::Transformer
  def call(filename, content)
    return unless content.has_key?("example")

    unless content.has_key?("schema") || content.has_key?("properties")
      content["example"] = [content["example"]].flatten
      content["examples"] = content.delete("example")
    end

    content
  end
end
