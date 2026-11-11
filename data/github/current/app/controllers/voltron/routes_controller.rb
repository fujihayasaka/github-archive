# typed: true
# frozen_string_literal: true

module Voltron
  class RoutesController < ApplicationController
    include FragmentController
    depends_on_clusters ApplicationRecord::Mysql1,
      only: [:show]

    # Exempt these actions from the GHES first run check to allow voltron to load routes
    skip_before_action :first_run_check if GitHub.enterprise?
    skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
    skip_before_action :validate_hmac, unless: -> { Rails.env.production? }

    def show
      render json: [
        {
          path: "/:user_id/:repository/commit/:name",
          metadata: { "controller": "commit", "action": "show" },
          root: {
            path: "/_view_fragments/Voltron::CommitFragmentsController/show/:user_id/:repository/:name/repo_layout",
            metadata: { namespace: "Voltron::CommitFragmentsController", page: "show", fragment: "repo_layout" },
            children: {
              header: {
                path: "/_view_fragments/Voltron::CommitFragmentsController/show/:user_id/:repository/:name/commit_show_header",
                metadata: { namespace: "Voltron::CommitFragmentsController", page: "show", fragment: "commit_show_header" },
              },
              content: {
                path: "/_view_fragments/Voltron::CommitFragmentsController/show/:user_id/:repository/:name/commit_show_contents",
                metadata: { namespace: "Voltron::CommitFragmentsController", page: "show", fragment: "commit_show_contents" },
              },
            },
          },
        },
        {
          path: "/:user_id/:repository/discussions/:discussion_number",
          metadata: {
            controller: "discussions",
            action: "show",
          },
          root: {
            path: "/_view_fragments/Voltron::DiscussionsFragmentsController/show/:user_id/:repository/:discussion_number/discussion_layout",
            metadata: {
              namespace: "Voltron::DiscussionsFragmentsController",
              page: "show",
              fragment: "discussion_layout",
            },
            children: {
              content_1: {
                path: "/_view_fragments/Voltron::DiscussionsFragmentsController/show/:user_id/:repository/:discussion_number/content_1",
                metadata: {
                  namespace: "Voltron::DiscussionsFragmentsController",
                  page: "show",
                  fragment: "content_1",
                },
                children: {
                  content_2: {
                    path: "/_view_fragments/Voltron::DiscussionsFragmentsController/show/:user_id/:repository/:discussion_number/content_2",
                    metadata: {
                      namespace: "Voltron::DiscussionsFragmentsController",
                      page: "show",
                      fragment: "content_2",
                    },
                  },
                },
              },
              sidebar: {
                path: "/_view_fragments/Voltron::DiscussionsFragmentsController/show/:user_id/:repository/:discussion_number/sidebar_content",
                metadata: {
                  namespace: "Voltron::DiscussionsFragmentsController",
                  page: "show",
                  fragment: "sidebar_content",
                },
              },
            },
          }
        },
        {
          path: "/:user_id/:repository/pull/:pr_number",
          metadata: {
            controller: "pull_requests",
            action: "show",
          },
          root: {
            path: "/_view_fragments/voltron/pull_requests/show/:user_id/:repository/:pr_number/pull_request_layout",
            metadata: {
              namespace: "Voltron::PullRequestsFragmentsController",
              page: "show",
              fragment: "pull_request_layout",
            },
            children: {
              content: {
                path: "/_view_fragments/voltron/pull_requests/show/:user_id/:repository/:pr_number/conversation_content",
                metadata: {
                  namespace: "Voltron::PullRequestsFragmentsController",
                  page: "show",
                  fragment: "conversation_content",
                },
              },
              sidebar: {
                path: "/_view_fragments/voltron/pull_requests/show/:user_id/:repository/:pr_number/conversation_sidebar",
                metadata: {
                  namespace: "Voltron::PullRequestsFragmentsController",
                  page: "show",
                  fragment: "conversation_sidebar",
                },
              },
            },
          }
        },
        {
          path: "/:user_id/:repository/issues/:id",
          metadata: {
            controller: "issues",
            action: "show",
          },
          root: {
            path: "/_view_fragments/issues/show/:user_id/:repository/:id/issue_layout",
            metadata: {
              namespace: "Voltron::IssuesFragmentsController",
              page: "show",
              fragment: "issue_layout",
            },
            children: {
              content: {
                path: "/_view_fragments/issues/show/:user_id/:repository/:id/issue_conversation_content",
                metadata: {
                  namespace: "Voltron::IssuesFragmentsController",
                  page: "show",
                  fragment: "issue_conversation_content",
                },
              }
            },
          }
        }
      ].to_json
    end
  end
end
