# typed: true
# frozen_string_literal: true

require "erb"

module OpenApi
  module CLI
    module Commands
      OPERATION_ID_ERROR_MSG = <<~ERR
        Invalid operation id `%s`. By convention we use two part IDs containing
        both a category and a unique ID. Ex: pulls/create
      ERR

      class CreateOperation < Command
        def run(operation_id)
          parts = operation_id.split("/")

          if parts.size != 2
            raise ArgumentError, OPERATION_ID_ERROR_MSG % operation_id
          end

          summary = ask("Short summary for this operation (Ex: 'Create an issue')", :green)

          path = ask("Operation HTTP path (ex: /users/{user_id})", :green)

          # Always have a leading forward slash
          if !path.start_with?("/")
            path = "/" + path
          end

          method = ask("Operation HTTP method (ex: get, post, put, patch)", :green).downcase

          tag, id = parts

          published = yes?("Operations described in our OpenAPI description are made public. Is this operation ready to be published?", :red)

          template_path = File.join(File.dirname(__FILE__), "../templates/operation.erb")
          rendered = ERB.new(File.read(template_path), trim_mode: "-").result_with_hash(
            tag: tag,
            summary: summary,
            slug: summary.downcase.strip.gsub(" ", "-").gsub(/[^\w-]/, ""),
            operation_id: operation_id,
            path: path,
            method: method,
            published: published,
          )

          new_operation_path = OpenApi.root.join("operations", tag, "#{id}.yaml")
          File.write(new_operation_path, rendered)
          say "Wrote operation `#{operation_id}` to `#{new_operation_path}`", :green
        end
      end
    end
  end
end
