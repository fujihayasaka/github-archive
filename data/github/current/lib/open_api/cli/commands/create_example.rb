# typed: true
# frozen_string_literal: true

require "erb"

module OpenApi
  module CLI
    module Commands

      class CreateExample < Command
        def run(schema, output:)
          schema_path = OpenApi.root.join("components", "schemas", "#{schema}.yaml")

          if !File.exist?(schema_path)
            raise ArgumentError, "Could not find schema `#{schema_path}`, make sure you specify a valid schema name."
          end

          generated = {
            "value" => generate_example_from_schema(YAML.load(File.read(schema_path)))
          }

          output_name = output || schema
          example_path = OpenApi.root.join("components", "examples", "#{output_name}.yaml")

          if File.exist?(example_path)
            raise ArgumentError, "An example already exists in `#{example_path}`. Use --output to specify a different path."
          end

          File.write(example_path, YAML.dump(generated))
          say "Wrote new example from schema `#{schema}` to `#{example_path}`", :green
        end

        private

        def generate_example_from_schema(schema)
          if ref = schema["$ref"]
            refed_schema = File.read(OpenApi.root.join("components", "schemas", ref))
            return generate_example_from_schema(YAML.load(refed_schema))
          end

          if schema["allOf"]
            $stderr.puts "allOf example generation is not supported, please create an example manually."
            return nil
          end

          if combined_schema = schema["oneOf"] || schema["anyOf"]
            $stderr.puts "Encountered a combined schema (oneOf, anyOf). Generating one example only.\n" +
                         "Please create additional examples for the other branches."
            return generate_example_from_schema(combined_schema.first)
          end

          case schema["type"]
          when "object"
            schema["properties"].reduce({}) do |example, (name, schema)|
              example[name] = generate_example_from_schema(schema)
              example
            end
          when "array"
            [generate_example_from_schema(schema["items"])]
          when nil
            $stderr.puts "Encountered a schema without a type, returning null"
            nil
          else
            return schema["example"] if schema["example"]
            generate_dummy_data_for_type(schema["type"])
          end
        end

        def generate_dummy_data_for_type(type)
          case type
          when "string"
            "<TODO>"
          when "integer", "number"
            rand(10)
          when "boolean"
            [true, false].sample
          else
            $stderr.puts "No dummy data for type #{type}, consider adding a generator."
          end
        end
      end
    end
  end
end
