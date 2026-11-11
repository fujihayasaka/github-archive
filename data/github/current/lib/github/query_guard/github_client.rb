#!/usr/bin/env ruby
# typed: true
# frozen_string_literal: true

require "sorbet-runtime"
require "faraday"
require "json"

module GitHub
  module QueryGuard
    class GitHubClient

      MAX_RETRIES = 2

      sig { params(token: String, inference_token: String).void }
      def initialize(token, inference_token)
        @token = token
        @inference_token = inference_token
      end

      sig { returns(Faraday::Connection) }
      def client
        @_conn ||= Faraday.new(url: "https://api.github.com") do |builder| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
          builder.request :authorization, "token", @token
          builder.request :json
          builder.response :json
          builder.response :raise_error
          builder.adapter Faraday.default_adapter
        end
      end

      sig { returns(Faraday::Connection) }
      def inference_client
        @_conn_inference ||= Faraday.new(url: "https://models.github.ai") do |builder| # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
          builder.request :authorization, "token", @inference_token
          builder.request :json
          builder.response :json
          builder.adapter Faraday.default_adapter
        end
      end

      sig { params(max_retries: Integer, block: T.proc.returns(Faraday::Response)).returns(Faraday::Response) }
      def with_retry(max_retries: MAX_RETRIES, &block)
        retries = 0
        begin
          response = block.call
          return response unless response.status >= 500 && response.status < 600
          raise Faraday::ServerError, "Server error: #{response.status}"
        rescue Faraday::ServerError
          retries += 1
          retry if retries <= max_retries
          raise
        end
      end

      module Commits
        extend T::Helpers
        requires_ancestor { GitHubClient }

        sig { params(repo: String, head: String, sha: String).returns(Faraday::Response) }
        def get_commit_compare(repo, head, sha)
          with_retry do
            client.get("/repos/#{repo}/compare/#{head}...#{sha}")
          end
        end
      end

      module Comments
        extend T::Helpers
        requires_ancestor { GitHubClient }

        sig { params(repo: String, pr_number: String).returns(Faraday::Response) }
        def get_comments(repo, pr_number)
          with_retry do
            client.get("/repos/#{repo}/issues/#{pr_number}/comments")
          end
        end

        sig { params(repo: String, pr_number: String, message: String).void }
        def post_comment(repo, pr_number, message)
          with_retry do
            client.post("/repos/#{repo}/issues/#{pr_number}/comments") do |req|
              req.body = { body: message }.to_json
            end
          end
        end
      end

      module PullRequest
        extend T::Helpers
        requires_ancestor { GitHubClient }

        sig { params(repo: String, pr_number: String).returns(Faraday::Response) }
        def get_diff(repo, pr_number)
          with_retry do
            client.get("/repos/#{repo}/pulls/#{pr_number}") do |req|
              req.headers["Accept"] = "application/vnd.github.v3.diff"
            end
          end
        end
      end

      module AI
        extend T::Helpers
        requires_ancestor { GitHubClient }

        sig { params(prompt: String, model: String).returns(Faraday::Response) }
        def infer(prompt, model)
          with_retry do
            inference_client.post("/inference/chat/completions") do |req|
              req.body = {
                messages: [
                  { role: "user", content: prompt }
                ],
                model: model,
                stream: false,
              }
            end
          end
        end
      end

      module Reviews
        extend T::Helpers
        requires_ancestor { GitHubClient }

        sig { params(repo: String, pr_number: String, commit_id: String, body: T.nilable(String), event: String, comments: T::Array[T::Hash[String, T.untyped]]).returns(Faraday::Response) }
        def create_review(repo, pr_number, commit_id, body, event, comments = [])
          with_retry do
            client.post("/repos/#{repo}/pulls/#{pr_number}/reviews") do |req|
              req.body = {
                commit_id: commit_id,
                event: event,
                comments: comments
              }
              req.body[:body] = body if body && !body.empty?
            end
          end
        end
      end

      include AI
      include Comments
      include Commits
      include PullRequest
      include Reviews
    end
  end
end
