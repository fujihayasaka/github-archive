# typed: true
# frozen_string_literal: true

module ElastomerClient
  class Client
    def inference(task_type, inference_id)
      Inference.new(self, task_type, inference_id)
    end

    class Inference
      attr_reader :client, :task_type, :inference_id

      def initialize(client, task_type, inference_id)
        @client = client
        @task_type = task_type
        @inference_id = inference_id
      end

      # https://www.elastic.co/docs/api/doc/elasticsearch/v8/operation/operation-inference-get-2
      def get(params = {})
        response = client.get "/_inference/{task_type}/{inference_id}", update_params(params, action: "inference.get", rest_api: "inference.get_model")
        response.body
      end

      # https://www.elastic.co/docs/api/doc/elasticsearch/v8/operation/operation-inference-put-1
      def create(body, params = {})
        response = client.put "/_inference/{task_type}/{inference_id}", update_params(params, body:, action: "inference.create", rest_api: "inference.put_model")
        response.body
      end

      # https://www.elastic.co/docs/api/doc/elasticsearch/v8/operation/operation-inference-update-1
      def update(body, params = {})
        response = client.put "/_inference/{task_type}/{inference_id}/_update", update_params(params, body:, action: "inference.update", rest_api: "inference.put_model")
        response.body
      end

      # https://www.elastic.co/docs/api/doc/elasticsearch/v8/operation/operation-inference-delete-1
      def delete(params = {})
        response = client.delete "/_inference/{task_type}/{inference_id}", update_params(params, action: "inference.delete", rest_api: "inference.delete_model")
        response.body
      end

      # https://www.elastic.co/docs/api/doc/elasticsearch/v8/operation/operation-inference-inference-1
      def perform(body, params = {})
        response = client.post "/_inference/{task_type}/{inference_id}", update_params(params, body:, action: "inference.perform", rest_api: "inference.inference")
        response.body
      end

      def update_params(params, overrides = nil)
        h = defaults.update params
        h.update overrides unless overrides.nil?
        h
      end

      # Internal: Returns a Hash containing default parameters.
      def defaults
        {
          task_type:,
          inference_id:,
        }
      end
    end
  end
end
