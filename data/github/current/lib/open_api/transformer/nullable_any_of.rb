# typed: true
# frozen_string_literal: true

class OpenApi::Transformer::NullableAnyOf < OpenApi::Transformer
  def call(filename, content)
    return unless content.has_key?("anyOf") && content.has_key?("nullable") && content["nullable"] == true
    content.delete("nullable")

    if content["type"]
      # if the anyOf has a type array already, then just add "null" as a new type
      content["type"] = Array(content["type"])
      content["type"] << "null"
    else
      # if there is no type string/array, then we need to make one based on the things
      # already in the anyOf array.
      content["type"] = ["null"]
      content["anyOf"].each do |item|
        if item.is_a?(Hash) && item.has_key?("$ref")
          content["type"] << "object"
        elsif item["type"]
          content["type"] << item["type"]
        else
          raise "unhandled anyOf item: #{item}"
        end
      end
    end

    content["type"].uniq!

    content
  end
end
