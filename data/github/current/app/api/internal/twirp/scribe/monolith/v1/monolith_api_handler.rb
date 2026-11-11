# typed: true
# frozen_string_literal: true

require "monolith-twirp-scribe-monolith"

module Api::Internal::Twirp::Scribe
  module Monolith
    module V1
      class MonolithApiHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["scribe"]
        handles_service Scribe::Monolith::V1::MonolithServiceAPIService

        # Public: Implementation of the GetProjectData Twirp RPC.
        #
        # req - The Twirp request as a Scribe::Monolith::V1::GetProjectDataRequest.
        # env - The Twirp environment as a Hash.
        #
        # Returns the Twirp response either as a
        # Scribe::Monolith::V1::GetProjectDataResponse, or a Twirp::Error.
        sig do
          params(
            req: Scribe::Monolith::V1::GetProjectDataRequest,
            env: T::Hash[String, T.untyped]
          ).returns(T.any(Scribe::Monolith::V1::GetProjectDataResponse, Twirp::Error))
        end
        def get_project_data(req, env)
          @current_user = User.find_by(id: req.viewer_id)
          return Twirp::Error.unauthenticated("viewer_id is required") if @current_user.nil?

          project = MemexProject.find_by(id: req.project_id)
          return Twirp::Error.not_found("project not found") if project.nil?

          unless project.viewer_can_read?(@current_user)
            return Twirp::Error.permission_denied("user does not have access to this project")
          end

          @filter_query = req.query
          project_data = fetch_project_data_via_graphql(project, @current_user)
          return project_data if project_data.is_a?(Twirp::Error)

          Scribe::Monolith::V1::GetProjectDataResponse.new(
            project_data_json: project_data.to_json
          )
        end

        private

        sig { params(project: MemexProject, viewer: User).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error)) }
        def fetch_project_data_via_graphql(project, viewer)
          owner = project.owner

          if owner.organization?
            fetch_organization_project_data(project, owner.login, viewer)
          else
            fetch_user_project_data(project, owner.login, viewer)
          end
        end

        sig { params(project: MemexProject, login: String, viewer: User).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error)) }
        def fetch_organization_project_data(project, login, viewer)
          query = <<-'GRAPHQL'
            query($projectNumber: Int!, $login: String!, $query: String) {
              organization(login: $login) {
          GRAPHQL

          query += PROJECT_QUERY

          execute_graphql_query(query, project.number, login, viewer, "organization")
        end

        sig { params(project: MemexProject, login: String, viewer: User).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error)) }
        def fetch_user_project_data(project, login, viewer)
          query = <<-'GRAPHQL'
            query($projectNumber: Int!, $login: String!, $query: String) {
              user(login: $login) {
          GRAPHQL

          query += PROJECT_QUERY

          execute_graphql_query(query, project.number, login, viewer, "user")
        end

        sig do
          params(
            query: String,
            project_number: Integer,
            login: String,
            viewer: User,
            query_field: String
          ).returns(T.any(T::Hash[Symbol, T.untyped], Twirp::Error))
        end
        def execute_graphql_query(query, project_number, login, viewer, query_field)
          variables = { projectNumber: project_number, login: login, query: @filter_query }

          begin
            result = Platform.execute(
              query,
              target: :public,
              context: {
                viewer:,
                feature_flags: [],
              },
              variables:,
            )

            if result.to_h["errors"].present?
              return Twirp::Error.internal("GraphQL query failed: #{result.to_h["errors"]}")
            end

            data = result.to_h.dig("data", query_field, "projectV2")
            return Twirp::Error.not_found("project data not found") if data.nil?

            data
          rescue StandardError => e
            Twirp::Error.internal("Failed to fetch project data: #{e.message}")
          end
        end

        PROJECT_QUERY = <<~'GRAPHQL'
              projectV2(number: $projectNumber) {
                title
                items(first: 100, query: $query) {
                  totalCount
                  nodes {
                    id
                    type
                    createdAt
                    updatedAt
                    content {
                      ... on Issue {
                        number
                        title
                        body
                        url
                        state
                        author {
                          login
                        }
                        repository {
                          name
                          owner {
                            login
                          }
                        }
                        comments(first: 100) {
                          nodes {
                            body
                            createdAt
                            updatedAt
                            author {
                              login
                            }
                          }
                        }
                      }
                      ... on PullRequest {
                        number
                        title
                        body
                        url
                        state
                        author {
                          login
                        }
                        repository {
                          name
                          owner {
                            login
                          }
                        }
                        comments(first: 100) {
                          nodes {
                            body
                            createdAt
                            updatedAt
                            author {
                              login
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        GRAPHQL
      end
    end
  end
end
