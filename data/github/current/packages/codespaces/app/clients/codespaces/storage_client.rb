# typed: true
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Codespaces
  # Public: Interface to the Azure Storage queues
  class StorageClient < Client
    extend T::Helpers

    DEFAULT_NUM_MESSAGES = 32
    class TimeoutError < Client::TimeoutError; end
    class ConnectionFailed < Client::ConnectionFailed; end
    class BadResponseError < Client::BadResponseError; end
    class EncryptionKeyError < Client::EncryptionKeyError; end

    class Message
      attr_reader :id, :pop_receipt, :body, :dequeue_count, :environment, :insertion_time, :expiration_time, :time_next_visible

      def initialize(id:, pop_receipt:, body:, dequeue_count:, environment: :production, insertion_time:, expiration_time:, time_next_visible:)
        @id, @pop_receipt, @body, @dequeue_count, @environment = id, pop_receipt, body, dequeue_count.to_i, environment
        @insertion_time = insertion_time
        @expiration_time = expiration_time
        @time_next_visible = time_next_visible
      end

      def event_id
        body["id"]
      end
    end

    class Request
      attr_accessor :response, :end_time, :http_method
      def initialize(method:, path:, body: nil, headers: {})
        @http_method = method
        @path = path
        @body = body
        @headers = headers
        @response = nil
        @end_time = nil
      end

      def execute(connection)
        self.response = connection.run_request(http_method, path, body, headers)
        self.end_time = GitHub::Dogstats.monotonic_time
        self
      end

      private

      attr_reader :path, :body, :headers
    end

    OAUTH_URL = "https://login.microsoftonline.com/"
    STORAGE_OAUTH_RESOURCE = "https://storage.azure.com/"
    # The queues in each of our accounts per region all happen to have the same name currently
    # If we add more than one queue per account, we'll need to update this logic
    QUEUE_NAME = "github-reporting-queue"

    attr_reader :storage_url, :queue_name, :environment, :account_name

    def initialize(account_name:, environment: :production, **kwargs)
      @account_name = account_name
      @environment = environment

      # we have switched to loading the details from the environment passed in, NOT the Rails.env
      # Rails.env will set up the configuration by loading config/environments/#{Rails.env}.rb
      @queue_name = QUEUE_NAME
      @storage_url = GitHub.codespaces_storage_accounts[:url_pattern] % { account_name: account_name }
      super **kwargs
    end

    def logger
      super do |l|
        l.filter(/(sig=)(\w+)/, '\1[REMOVED]')
        l.log_context = {
          "gh.codespaces.storage_client.storage_url" => storage_url,
          "gh.codespaces.storage_client.queue_name" => queue_name,
          "gh.codespaces.storage_client.environment" => environment
        }
      end
    end

    # Gets messages from the environment-specific queue for in the Storage queue named `account_name`
    #
    # Returns an Array of Nokogiri::XML::NodeSet QueueMessage objects
    #
    # See https://docs.microsoft.com/en-us/rest/api/storageservices/get-messages#sample-response
    def get_messages(number_of_messages: DEFAULT_NUM_MESSAGES, visibility_timeout: nil)
      query_string = {
        numofmessages: number_of_messages,
        visibilitytimeout: visibility_timeout
      }.compact.to_query
      messages = GitHub.dogstats.distribution_time("codespaces.storage_client.get_messages.latency", tags: ["vscs.environment:#{environment}"]) do
        parsed_storage_api(
          :get,
          "/#{queue_name}/messages?#{query_string}",
          tags: ["codespaces_storage_client:get_messages", "account_name:#{account_name}"]
        )
      end

      messages.xpath("//QueueMessage").map do |message|
        Message.new(
          id: message.xpath("MessageId").text,
          pop_receipt: message.xpath("PopReceipt").text,
          body: GitHub::JSON.parse(Base64.decode64(message.xpath("MessageText").text)),
          dequeue_count: message.xpath("DequeueCount").text,
          environment: @environment,
          insertion_time: message.xpath("InsertionTime").text,
          expiration_time: message.xpath("ExpirationTime").text,
          time_next_visible: message.xpath("TimeNextVisible").text,
        )
      end
    end

    def approximate_messages_count
      queue_metadata.headers["x-ms-approximate-messages-count"].to_i
    end

    def delete_messages(messages)
      messages.map do |message|
        path = "/#{queue_name}/messages/#{message.id}?#{message.pop_receipt.to_query("popreceipt")}"
        path_with_key = add_sas_key_to_path(path)
        Request.new(method: :delete, path: path_with_key)
      end
        # Running in parallel since these requests can take up to a second to respond.
        .then { |requests| run_in_parallel(requests) }
    end

    private

    # Returns an empty response with a set of response headers with metadata about the queue
    #
    # See: https://docs.microsoft.com/en-us/rest/api/storageservices/get-queue-metadata
    def queue_metadata
      GitHub.dogstats.distribution_time("codespaces.storage_client.get_queue_metadata.latency") do
        storage_api(
          :get,
          "/#{queue_name}?comp=metadata",
          tags: ["codespaces_storage_client:get_queue_metadata", "environment:#{environment}", "account_name:#{account_name}"]
        )
      end
    end

    def storage_api(method, path, body: {}, tags:)
      start_time = GitHub::Dogstats.monotonic_time
      path_with_key = add_sas_key_to_path(path)

      resp = if method == :get
        storage_connection.get(path_with_key, body)
      else
        storage_connection.run_request(method, path_with_key, body, nil)
      end

      caller_base_label = caller_locations(1, 1)&.first&.base_label
      all_tags = ["caller:#{caller_base_label}", "status:#{resp.status}"].concat(tags)
      GitHub.dogstats.distribution("codespaces.client.storage.response.latency", GitHub::Dogstats.duration(start_time, GitHub::Dogstats.monotonic_time), tags: all_tags + ["vscs.environment:#{environment}"])

      if resp.success?
        resp
      else
        raise BadResponseError, request_err_message("Bad response", method)
      end
    rescue Faraday::TimeoutError
      raise TimeoutError, request_err_message("Timeout exceeded", method)
    rescue Faraday::ConnectionFailed => e
      raise ConnectionFailed, request_err_message("Connection failed: #{e.message}", method)
    end

    def run_in_parallel(requests)
      start_time = GitHub::Dogstats.monotonic_time
      caller_base_label = caller_locations(1, 1)&.first&.base_label

      conn = connection_for(storage_url, adapter: :typhoeus)
      requests.each do |request|
        conn.in_parallel do
          GitHub.dogstats.distribution_time("codespaces.storage_client.#{caller_base_label}.latency", tags: ["vscs.environment:#{environment}"]) do
            request.execute(conn)
          rescue Faraday::TimeoutError
            request.response = TimeoutError.new(request_err_message("Timeout exceeded", request.http_method))
          rescue Faraday::ConnectionFailed => e
            request.response = ConnectionFailed.new(request_err_message("Connection failed: #{e.message}", request.http_method))
          end
        end
      end.then { |requests| interpret_parallel_responses(requests, start_time) }
    end

    def interpret_parallel_responses(requests, start_time)
      caller_base_label = caller_locations(4, 1)&.first&.base_label
      requests.map do |request, _end_time|
        response = request.response
        next response unless response.is_a?(Faraday::Response)

        tags = [
          "caller:#{caller_base_label}",
          "status:#{response.status}",
          "codespaces_storage_client:#{caller_base_label}",
          "account_name:#{account_name}",
        ]

        GitHub.dogstats.distribution("codespaces.client.storage.response.latency", GitHub::Dogstats.duration(start_time, GitHub::Dogstats.monotonic_time), tags: tags + ["vscs.environment:#{environment}"])

        next response if response.success?

        BadResponseError.new(request_err_message("Bad response", response.env.method))
      end
    end

    def parsed_storage_api(method, path, body: {}, tags:)
      resp = storage_api(method, path, body: body, tags: tags)
      Nokogiri::XML(resp.body) { |config| config.strict }
    rescue Nokogiri::XML::SyntaxError
      raise BadResponseError, request_err_message("Bad response", method, "invalid XML")
    end

    def fetch_sas_key
      @accounts ||= Codespaces::VscsClient.fetch_storage_accounts_and_tokens(vscs_target: @environment)
      @accounts[@account_name]
    end

    def add_sas_key_to_path(path)
      sas_key = fetch_sas_key
      raise "No SAS key found for the given account name: '#{@account_name}'" if sas_key.nil?

      u = URI(path)
      query_args = URI.decode_www_form(u.query || "") + URI.decode_www_form(sas_key)
      u.query = URI.encode_www_form(query_args)
      u.to_s
    end

    def storage_connection
      @storage_connection ||= begin
        options = {
          keepalive: {
            time: 60,
            intvl: 5,
            probes: 3,
          }
        }
        connection_for(storage_url, **options)
      end
    end
  end
end
