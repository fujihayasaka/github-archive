# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

get "/pull/:id/prx", to: "pull_requests_react#prx", id: /\d+/
post "/toggle_new_mergebox", to: "pull_requests_react#toggle_new_mergebox", as: :toggle_new_mergebox
post "/toggle_new_commits", to: "pull_requests_react#toggle_new_commits", as: :toggle_new_commits
post "/toggle_generic_feature", to: "pull_requests_react#toggle_generic_feature", as: :toggle_generic_feature

get "/pull/:id/page_data/status_checks", to: "pull_requests/page_data/shared#status_checks", id: /\d+/, format: "json"
get "/pull/:id/page_data/commits", to: "pull_requests/page_data/shared#commits", id: /\d+/, format: "json"
get "pull/:id/page_data/merge_box", to: "pull_requests/page_data/shared#merge_box", id: /\d+/, format: "json"
get "pull/:id/page_data/merge_instructions", to: "pull_requests/page_data/shared#merge_instructions", id: /\d+/, format: "json"
get "pull/:id/page_data/viewed_files_count", to: "pull_requests/page_data/shared#viewed_files_count", id: /\d+/, format: "json"

# Header routes
get "/pull/:id/page_data/header", to: "pull_requests/page_data/shared#header", id: /\d+/, format: "json"
get "/pull/:id/page_data/code_button", to: "pull_requests/page_data/shared#code_button", id: /\d+/, format: "json"
get "/pull/:id/page_data/tab_counts", to: "pull_requests/page_data/shared#tab_counts", id: /\d+/, format: "json"

# Mutations
patch "/pull/:id/page_data/change_base", to: "pull_requests/page_data/shared#change_base", id: /\d+/, format: "json"
patch "/pull/:id/page_data/update_title", to: "pull_requests/page_data/shared#update_title", id: /\d+/, format: "json"
post "/pull/:id/page_data/enable_auto_merge", to: "pull_requests/page_data/mutations#enable_auto_merge", id: /\d+/, format: "json"
post "/pull/:id/page_data/disable_auto_merge", to: "pull_requests/page_data/mutations#disable_auto_merge", id: /\d+/, format: "json"
post "/pull/:id/page_data/restore_head_ref", to: "pull_requests/page_data/mutations#restore_head_ref", id: /\d+/, format: "json"
post "/pull/:id/page_data/delete_head_ref", to: "pull_requests/page_data/mutations#delete_head_ref", id: /\d+/, format: "json"
post "/pull/:id/page_data/mark_ready_for_review", to: "pull_requests/page_data/mutations#mark_ready_for_review", id: /\d+/, format: "json"
post "/pull/:id/page_data/merge", to: "pull_requests/page_data/mutations#merge", id: /\d+/, format: "json"
post "/pull/:id/page_data/dequeue_pull_request", to: "pull_requests/page_data/mutations#dequeue_pull_request", id: /\d+/, format: "json"
post "/pull/:id/page_data/update_pull_request_branch", to: "pull_requests/page_data/mutations#update_pull_request_branch", id: /\d+/, format: "json"
post "/pull/:id/page_data/dismiss_review", to: "pull_requests/page_data/mutations#dismiss_review", id: /\d+/, format: "json"
post "/pull/:id/page_data/re_request_review_from_user", to: "pull_requests/page_data/mutations#re_request_review_from_user", id: /\d+/, format: "json"
post "/pull/:id/page_data/re_request_review_from_team", to: "pull_requests/page_data/mutations#re_request_review_from_team", id: /\d+/, format: "json"
