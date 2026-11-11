# typed: true
# frozen_string_literal: true

module OpenApi
  module CLI
    module Operations
      def self.operation_full(openapi)
        openapi["paths"].flat_map do |_path, operation|
          operation.map do |_method, op|
            begin
              contents = YAML.safe_load(File.read(OpenApi.root.join(op["$ref"])))
            rescue Errno::ENOENT
              next nil
            end

            next contents
          end
        end
      end

      def self.get_operation_owners_payload(releases)
        operations_owner_payload = {}

        releases.each do |release|
          new_operations = OpenApi::CLI::Operations::operation_full(release.content)

          new_operations.each do |operation|
            path = operation["x-github-internal"]["path"]
            path_value = OpenApi::CLI::Operations::operation_owner_hash(operation)

            existing_value = operations_owner_payload[path]

            if existing_value.nil?
              operations_owner_payload[path] = [path_value]
            else
              has_matching_value = existing_value.any? { |value| value["id"] == path_value["id"] }
              unless has_matching_value
                operations_owner_payload[path] = existing_value.append(path_value)
              end
            end
          end
        end

        # ensure hash is sorted by key, not by insertion order
        operations_owner_payload.sort.to_h
      end

      def self.operation_owner_hash(operation)
        id = operation["operationId"]
        summary = operation["summary"]
        metadata = operation["x-github-internal"]
        releases = operation["x-github-releases"]

        owner = metadata["owner"] || "unknown"
        http_method = metadata["http-method"]
        published = metadata["published"]
        external_url = operation["externalDocs"]["url"]
        url_fragment = external_url.partition("#")[2]

        {
          "id" => id,
          "http-method" => http_method,
          "summary" => summary,
          "owner" => owner,
          "published" => published,
          "releases" => releases,
          "url-fragment" => url_fragment,
        }
      end
    end
  end
end
