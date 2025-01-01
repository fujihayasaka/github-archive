# typed: true
# frozen_string_literal: true

require "monolith-twirp-pages-pagesdeployerapi"

class Page
  module Twirp
    class RequestClient
      class StatusRequestError < StandardError; end
      ValidateUrlResponse = Struct.new(:valid, :error)

      attr_reader :client

      # Public: Construct a CreateImportClient.
      #
      # faraday_connection - A Faraday::Connection instance.
      def initialize(service_name: "pages", faraday_connection: nil)
        faraday_connection ||= ConnectionBuilder.new(service_name: service_name).build
        @client = MonolithTwirp::Pages::Pagesdeployerapi::V1::DeploymentAPIClient.new(faraday_connection)
      end

      def record_not_found?(message)
        return false unless message.include?("redigo: nil returned")
        true
      end

      def request_deployment(deployment_id:, repository_id:, ref:)
        response = client.request_deployment(
          deployment_id: deployment_id.to_s,
          repository_id: repository_id.to_s,
          ref: ref.to_s.b
        )
        if response.error
          return nil
        end
        response.data.deployment_id
      end

      def validate_url(url:, repository_id:)
        response = client.validate_url(
          url: url,
          repository_id: repository_id
        )

        if response.error
          return ValidateUrlResponse.new(valid: "false", error: "unknown error: #{response.error.msg}")
        end

        ValidateUrlResponse.new(
          valid: response.data.valid,
          error: response.data.error,
        )
      end

      def get_status(deployment_id:, repository_id:, owner_id:)
        response = client.get_status(
          deployment_id: deployment_id.to_s,
          repository_id: repository_id.to_s,
          owner_id: owner_id.to_s
        )

        if response.error
          if record_not_found?(response.error.msg)
            return "not_found"
          else
            # Likely due to redis infra error, and we'll not want to expose it to user.
            return "unknown_status"
          end

        end
        response.data.status
      end

      def update_status(deployment_id:, repository_id:, status:)
        response = client.update_status(
          deployment_id: deployment_id.to_s,
          repository_id: repository_id.to_s,
          status: status
        )
        response.error
      end

      def clear_status(deployment_id:, repository_id:)
        response = client.clear_status(
          deployment_id: deployment_id.to_s,
          repository_id: repository_id.to_s
        )
        raise StatusRequestError.new, response.error if response.error
        true
      end

      def process_updates(pages_to_update)
        converted_pages = pages_to_update.map do |page|
          MonolithTwirp::Pages::Pagesdeployerapi::V1::PageToUpdate.new(
            custom_subdomain: page.custom_subdomain,
            page_id: page.id.to_s,
            subdomain: page.subdomain,
            visibility: Google::Protobuf::BoolValue.new(value: page.public)
          )
        end

        client.process_updates(pages: converted_pages)
      end

      def process_deletion(pages_to_delete)
        converted_pages = pages_to_delete.map do |page_id|
          MonolithTwirp::Pages::Pagesdeployerapi::V1::PageToDelete.new(page_id: page_id.to_s)
        end

        client.process_deletion(pages: converted_pages)
      end

      def request_deployment_hosts(page_id = "", deployment_id = "")
        response = client.get_deployment_host({
          page_id: page_id,
          deployment_id: deployment_id.to_s,
        })
        if response.error
          GitHub.logger.error("pages.request_deployment_hosts", {
            :exception => response.error,
            "code.namespace" => "Page::Twrip::RequestClient",
            "code.function" => "request_deployment_hosts",
            "gh.catalog_service" => "github/pages"
            })
          return []
        end
        response.data.hosts
      end

      def update_replica(page_id:, deployment_id:, replica_to_add:, replica_to_remove:, path: "")
        response = client.update_replica({
          page_id: page_id.to_s,
          deployment_id: deployment_id.to_s,
          replica_to_add: replica_to_add,
          replica_to_remove: replica_to_remove,
          path: path,
        })
        raise StatusRequestError.new, response.error if response.error
        true
      end
    end
  end
end
