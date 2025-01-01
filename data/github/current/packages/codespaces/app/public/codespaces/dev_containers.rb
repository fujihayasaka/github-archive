# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

require "hashids"

module Codespaces::DevContainers

  TEMPLATE_UNIVERSAL_EMPTY = JSON.pretty_generate({ image: "mcr.microsoft.com/devcontainers/universal:2", features: {} })

  # Placeholder data for now
  TEMPORARY_DEV_CONTAINER_TEMPLATES = <<-EOF
  [
    {
      "id": "go",
      "name": "Go",
      "description": "Develop Go based applications. Includes appropriate runtime args, Go, common tools, extensions, and dependencies.",
      "categories": [
        "Core",
        "Languages"
      ],
      "image": {
        "manifest": "https://mcr.microsoft.com/v2/devcontainers/go/tags/list"
      },
      "type": "singleContainer",
      "options": {
        "VARIANT": {
          "type": "string",
          "proposals": [
            "1",
            "1.19",
            "1.18"
          ],
          "default": "1"
        },
        "NODE_VERSION": {
          "type": "string",
          "proposals": [
            "none",
            "lts/*",
            "18",
            "16",
            "14"
          ],
          "default": "none"
        }
      }
    },
    {
      "id": "ruby",
      "name": "Ruby",
      "description": "Develop Ruby apps.",
      "categories": [
        "Core",
        "Languages"
      ]
    },
    {
      "id": "dotnet",
      "name": "Dotnet",
      "description": "Develop dotnet apps.",
      "categories": [
        "Core",
        "Languages"
      ]
    },
    {
      "id": "rust",
      "name": "Rust",
      "description": "Develop rust apps.",
      "categories": [
        "Core",
        "Languages"
      ]
    },
    {
      "id": "swift",
      "name": "Swift",
      "description": "Develop swift apps.",
      "categories": [
        "Core",
        "Languages"
      ]
    }
  ]
  EOF

  def self.devcontainer_collection_metadata
    # TODO Optimize: In-memory cache for now with expiration
    #                In the future, ingest into DB?
    response = external_faraday_client.get("https://containers.dev/static/devcontainer-index.json")
    Rails.logger.info("Codespaces::DevContainers::devcontainer_collection_metadata: #{response.status}")
    JSON.parse(response.body)
  end

  def self.dev_container_collection_metadata_for_templates
    # result = []
    # metadata = devcontainer_collection_metadata
    # metadata["collections"].each do |collection|
    #   # Append templates to global variable
    #   collection["templates"].each do |template|
    #     result.append(template)
    #   end
    # end
    # result

    JSON.parse(Codespaces::DevContainers::TEMPORARY_DEV_CONTAINER_TEMPLATES)
  end

  def self.dev_container_collection_metadata_for_features
    result = []
    metadata = devcontainer_collection_metadata
    metadata["collections"].each do |collection|
      # Append Features to global variable
      collection["features"].each do |feature|
        result.append(feature)
      end
    end
    result.sort_by { |f| f["name"] }
  end

  def self.dev_container_feature_from_id(params)
    features = dev_container_collection_metadata_for_features
    decoded_feature_id = Base64.decode64(params[:feature_id])
    features.find { |f| f["id"] == decoded_feature_id }
  end

  def self.external_faraday_client
    GitHub::FaradayClient::External.new do |conn|
      conn.adapter Faraday.default_adapter
    end
  end
  private_class_method :external_faraday_client
end
