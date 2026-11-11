# typed: true
# frozen_string_literal: true

class OpenApi::Transformer::NullableOneOf < OpenApi::Transformer
  def call(filename, content)
    return unless content.has_key?("oneOf") && content.has_key?("nullable") && content["nullable"] == true
    content.delete("nullable")

    if content["type"]
      # if the oneOf has a type array already, then just add "null" as a new type
      content["type"] = Array(content["type"])
      content["type"] << "null"
    else
      # if there is no type string/array, then we need to make one based on the things
      # already in the oneOf array.
      content["type"] = ["null"]
      content["oneOf"].each do |item|
        if item.is_a?(Hash) && item.has_key?("$ref")
          content["type"] << "object"
        elsif item["type"]
          content["type"] << item["type"]
        else
          raise "unhandled oneOf item: #{item}"
        end
      end
    end

    content["type"].uniq!

    content
  end
end
