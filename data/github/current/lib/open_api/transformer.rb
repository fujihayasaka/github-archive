# typed: true
# frozen_string_literal: true

module OpenApi
  class Transformer
    autoload :NullableOneOf, "open_api/transformer/nullable_one_of"
    autoload :NullableAnyOf, "open_api/transformer/nullable_any_of"
    autoload :NullableString, "open_api/transformer/nullable_string"
    autoload :NullableSchema, "open_api/transformer/nullable_schema"
    autoload :XNullableRef, "open_api/transformer/x_nullable_ref"
    autoload :Example, "open_api/transformer/example"

    ALL = {
      "config" => [],
      "operations" => [
        OpenApi::Transformer::NullableOneOf,
        OpenApi::Transformer::NullableAnyOf,
        OpenApi::Transformer::NullableString,
        OpenApi::Transformer::NullableSchema,
        OpenApi::Transformer::XNullableRef,
        OpenApi::Transformer::Example,
      ],
      "components" => [
        OpenApi::Transformer::NullableOneOf,
        OpenApi::Transformer::NullableAnyOf,
        OpenApi::Transformer::NullableString,
        OpenApi::Transformer::NullableSchema,
        OpenApi::Transformer::XNullableRef,
        OpenApi::Transformer::Example,
      ],
    }

    def self.transforming?
      !!ENV["OPENAPI_TRANSFORM"]
    end

    def self.transform!
      ALL.keys.each do |type|
        files = {}

        Dir.glob(OpenApi.root.join(type) + "**/*.yaml").each do |file|
          files[file] = YAML.load(File.read(file))
        end

        files.each do |filename, content|
          ALL[type].each do |transformer|
            old_content = content.deep_dup
            new_content = visit(filename, content, transformer.new)

            if old_content != new_content
              write(filename, new_content)
            end
          end
        end
      end
    end

    def self.write(filename, content)
      yaml = YAML.dump(content)
      File.open(filename, "w+") { |f| f.write(yaml) }
    end

    def self.visit(filename, content, visitor)
      case content
      when Array
        content.each do |child|
          if child.is_a?(Hash)
            visit(filename, child, visitor)
          end
        end
      when Hash
        visitor.call(filename, content)

        content.each_value do |child|
          if child.is_a?(Hash) || child.is_a?(Array)
            visit(filename, child, visitor)
          end
        end
      end
    end

    def call(_filename, _content)
      raise NotImplementedError, "The #call method must be defined in a subclass"
    end
  end
end
