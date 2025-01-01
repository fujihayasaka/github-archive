# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    class TableClient
      attr_reader :http_client, :host, :table_name
      attr_accessor :sas_token

      def initialize(http_client:, storage_account_name:, table_name:, sas_token: "")
        raise ArgumentError, "storage_account_name cannot be blank" if storage_account_name.blank?
        raise ArgumentError, "table_name cannot be blank" if table_name.blank?

        azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_azure_environment

        @http_client = http_client
        @host = "#{storage_account_name}.table#{azure_environment.storage_endpoint_suffix}"
        @table_name = table_name
        @sas_token = sas_token
      end

      def headers
        {
          Date: Time.now.utc.to_s,
          "x-ms-version": "2019-12-12",
          Accept: "application/json;odata=nometadata"
        }
      end

      def get(partition_key:, row_key:)
        encoded_partition_value = ERB::Util.url_encode(partition_key)
        encoded_row_value = ERB::Util.url_encode(row_key)
        uri = URI::HTTPS.build(host: @host, path: "/#{table_name}(PartitionKey='#{encoded_partition_value}',RowKey='#{encoded_row_value}')")
        http_client.send_request(method: :get, uri: uri, headers: headers)
      end

      def query(filter:, projected_columns: nil)
        escaped_filter = ERB::Util.url_encode(filter)
        columns = projected_columns ? "&$select=#{ERB::Util.url_encode(projected_columns)}" : ""
        query = "#{@sas_token}&$filter=#{escaped_filter}#{columns}"
        uri_base = URI::HTTPS.build(host: @host, path: "/#{table_name}()")

        uri = URI("#{uri_base}#{query}")
        http_client.send_request(method: :get, uri: uri, headers: headers)
      end

      def insert(entity:)
        insert_internal(method: :post, entity: entity)
      end

      def insert_or_merge(entity:)
        insert_internal(method: :merge, entity: entity)
      end

      def insert_or_replace(entity:)
        insert_internal(method: :put, entity: entity)
      end

      def delete(partition_key:, row_key:, etag: "*")
        unless [partition_key, row_key].all?
          raise ArgumentError, "parameter(s) missing partition_key=#{partition_key.nil?}, row_key=#{row_key.nil?}"
        end

        encoded_partition_value = ERB::Util.url_encode(partition_key)
        encoded_row_value = ERB::Util.url_encode(row_key)

        delete_headers = headers
        delete_headers["If-Match"] = etag

        uri_base = URI::HTTPS.build(host: @host, path: "/#{table_name}(PartitionKey='#{encoded_partition_value}',RowKey='#{encoded_row_value}')")
        uri = URI("#{uri_base}#{@sas_token}")

        http_client.send_request(method: :delete, uri: uri, headers: delete_headers)
      end

      private

      def insert_internal(method:, entity:)
        unless entity
          raise ArgumentError, "Entity and/or method is empty or nil"
        end
        unless method.in?([:post, :merge, :put])
          raise ArgumentError, "Method must be POST, MERGE, or PUT (should be unreachable)"
        end

        if method != :post
          unless [entity["PartitionKey"], entity["RowKey"]].all?
            raise ArgumentError, "parameter(s) missing partition_key=#{entity["PartitionKey"].nil?}, row_key=#{entity["RowKey"].nil?}"
          end

          encoded_partition_value = ERB::Util.url_encode(entity["PartitionKey"])
          encoded_row_value = ERB::Util.url_encode(entity["RowKey"])
        end

        case method
        when :post
          uri_base = URI::HTTPS.build(host: @host, path: "/#{table_name}()")
        when :merge, :put
          uri_base = URI::HTTPS.build(host: @host, path: "/#{table_name}(PartitionKey='#{encoded_partition_value}',RowKey='#{encoded_row_value}')")
        end
        uri = URI("#{uri_base}#{@sas_token}")
        http_client.send_request(method: method, uri: uri, headers: headers, body: entity)
      end
    end
  end
end
