# typed: true
# frozen_string_literal: true

require "thor"
require "erb"

module OpenApi
  module CLI
    module Commands
      class Create < Thor
        desc "operation <operation_id>", "Generate an OpenAPI operation"
        def operation(operation_id)
          OpenApi::CLI::Commands::CreateOperation.run(@shell, operation_id)
        end

        desc "example <schema>", "Generate an OpenAPI example for a given schema"
        method_option :output, aliases: "-o"
        def example(schema)
          OpenApi::CLI::Commands::CreateExample.run(shell, schema, output: options[:output])
        end
      end
    end
  end
end
