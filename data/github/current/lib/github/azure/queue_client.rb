# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    class QueueClient
      attr_reader :host

      # https://docs.microsoft.com/en-us/rest/api/storageservices/get-messages#uri-parameters
      # The maximum number of messages you can get in one request is 32.
      MAX_MESSAGES_TO_GET = 32
      attr_accessor :sas_token

      class Message
        attr_reader :id, :pop_receipt, :content, :dequeue_count

        def initialize(id:, pop_receipt:, dequeue_count:, content:)
          @id = id
          @pop_receipt = pop_receipt
          @dequeue_count = dequeue_count
          @content = content
        end

        def ==(other)
          @id == other&.id && @content == other&.content
        end
      end

      def initialize(http_client:, storage_account_name:, queue_name:, sas_token: "")
        raise ArgumentError, "storage_account_name cannot be blank" if storage_account_name.blank?
        raise ArgumentError, "queue_name cannot be blank" if queue_name.blank?

        azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_azure_environment

        @http_client = http_client
        @host = "#{storage_account_name}.queue#{azure_environment.storage_endpoint_suffix}"
        @base_path = "/#{queue_name}/messages"
        @sas_token = sas_token
      end

      def headers
        {
          Date: Time.now.utc.to_s,
          "x-ms-version": "2019-12-12",
        }
      end

      # Ref: https://docs.microsoft.com/en-us/rest/api/storageservices/put-message
      def put_message(message_content:, visibility_timeout: nil, message_ttl: nil, request_timeout: nil)
        unless message_content
          raise ArgumentError, "required parameter 'message_content' is nil"
        end

        query_hash = {
          "visibilitytimeout": visibility_timeout,
          "messagettl": message_ttl,
          "timeout": request_timeout
        }

        uri = build_uri(path: @base_path, query_hash: query_hash)
        body = Nokogiri::XML::Builder.new do |xml|
          xml.QueueMessage do
            xml.MessageText message_content.to_s
          end
        end

        @http_client.send_request(method: :post, uri: uri, headers: headers, body: body.to_xml)
      end

      def get_message(visibility_timeout: nil, request_timeout: nil)
        get_messages(num_of_messages: 1, visibility_timeout: visibility_timeout, request_timeout: request_timeout)
      end

      # Ref: https://docs.microsoft.com/en-us/rest/api/storageservices/get-messages
      def get_messages(num_of_messages: MAX_MESSAGES_TO_GET, visibility_timeout: nil, request_timeout: nil)
        raise ArgumentError, "maximum number of messages retrievable in one request is #{MAX_MESSAGES_TO_GET}" if num_of_messages > MAX_MESSAGES_TO_GET

        query_hash = {
          "numofmessages": num_of_messages,
          "visibilitytimeout": visibility_timeout,
          "timeout": request_timeout
        }

        uri = build_uri(path: @base_path, query_hash: query_hash)
        response = @http_client.send_request(method: :get, uri: uri, headers: headers)
        parse_response(response: response)
      end

      def peek_message(request_timeout: nil)
        peek_messages(num_of_messages: 1, request_timeout: request_timeout)
      end

      # Ref: https://docs.microsoft.com/en-us/rest/api/storageservices/get-messages
      def peek_messages(num_of_messages: nil, request_timeout: nil)
        query_hash = {
          "numofmessages": num_of_messages,
          "timeout": request_timeout,
          "peekonly": true
        }

        uri = build_uri(path: @base_path, query_hash: query_hash)
        response = @http_client.send_request(method: :get, uri: uri, headers: headers)
        parse_response(response: response)
      end

      # Ref: https://docs.microsoft.com/en-us/rest/api/storageservices/delete-message2
      def delete_message(message_id:, pop_receipt:, request_timeout: nil)
        unless [message_id, pop_receipt].all?(&:present?)
          raise ArgumentError, "required parameter(s) cannot be nil or blank('true' for nil/blank), message_id:#{message_id.blank?}, pop_receipt:#{pop_receipt.blank?}"
        end

        query_hash = {
          "popreceipt": pop_receipt,
          "timeout": request_timeout
        }

        uri = build_uri(path: "#{@base_path}/#{message_id}", query_hash: query_hash)
        @http_client.send_request(method: :delete, uri: uri, headers: headers)
      end

      # Ref: https://docs.microsoft.com/en-us/rest/api/storageservices/clear-messages
      def delete_all_messages(request_timeout: nil)
        query_hash = {
          "timeout": request_timeout
        }

        uri = build_uri(path: @base_path, query_hash: query_hash)
        @http_client.send_request(method: :delete, uri: uri, headers: headers)
      end

      # Ref: https://docs.microsoft.com/en-us/rest/api/storageservices/update-message
      def update_message(message_id:, message_content:, pop_receipt:, visibility_timeout:, request_timeout: nil)
        unless message_content
          raise ArgumentError, "required parameter 'message_content' is nil"
        end

        unless [message_id, pop_receipt, visibility_timeout].all?(&:present?)
          raise ArgumentError, "One or more required parameters are nil or blank ('true' for nil/blank):"\
                               "\n message_id:#{message_id.blank?},\n pop_receipt:#{pop_receipt.blank?},"\
                               "\n visibility_timeout:#{visibility_timeout.blank?}"
        end

        query_hash = {
          "visibilitytimeout": visibility_timeout,
          "popreceipt": pop_receipt,
          "timeout": request_timeout
        }

        uri = build_uri(path: "#{@base_path}/#{message_id}", query_hash: query_hash)
        body = Nokogiri::XML::Builder.new do |xml|
          xml.QueueMessage do
            xml.MessageText message_content.to_s
          end
        end

        @http_client.send_request(method: :put, uri: uri, headers: headers, body: body.to_xml)
      end

      private

      def parse_response(response:)
        Nokogiri::XML(response.body).xpath("//QueueMessage").map do |message|
          Message.new(
            id: message.xpath("MessageId").text,
            pop_receipt: message.xpath("PopReceipt").text,
            content: message.xpath("MessageText").text,
            dequeue_count: message.xpath("DequeueCount").text
          )
        end
      end

      def build_uri(path:, query_hash:)
        query = query_hash.compact.empty? ? @sas_token : query_hash.compact.to_query + "&#{@sas_token}"
        uri = URI::HTTPS.build(host: @host, path: path)
        URI("#{uri}#{@sas_token}&#{query_hash.compact.to_query}")
      end

    end
  end
end
