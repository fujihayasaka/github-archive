# typed: true
# frozen_string_literal: true

T.bind(self, ActionDispatch::Routing::Mapper)

post "/toggle_new_mergebox", to: "pull_requests_react#toggle_new_mergebox", as: :toggle_new_mergebox
post "/toggle_generic_feature", to: "pull_requests_react#toggle_generic_feature", as: :toggle_generic_feature

get "/pull/:id/page_data/status_checks", to: "pull_requests/page_data/shared#status_checks", id: /\d+/, format: "json"
get "/pull/:id/page_data/commits", to: "pull_requests/page_data/shared#commits", id: /\d+/, format: "json"
get "pull/:id/page_data/merge_box", to: "pull_requests/page_data/shared#merge_box", id: /\d+/, format: "json"
get "pull/:id/page_data/merge_instructions", to: "pull_requests/page_data/shared#merge_instructions", id: /\d+/, format: "json"
get "pull/:id/page_data/pending_review", to: "pull_requests/page_data/shared#pending_review", id: /\d+/, format: "json"
get "pull/:id/page_data/viewed_files_count", to: "pull_requests/page_data/shared#viewed_files_count", id: /\d+/, format: "json"
get "pull/:id/page_data/thread_previews", to: "pull_requests/page_data/shared#thread_previews", id: /\d+/, format: "json"
get "pull/:id/copilot_diff_chat", to: "pull_requests/page_data/shared#copilot_diff_chat", as: :pull_request_copilot_diff_chat
get "pull/:id/copilot_code_review_show_upsell", to: "pull_requests/page_data/shared#copilot_code_review_show_upsell", id: /\d+/, format: "json"
post "pull/:id/copilot_code_review_dismiss_upsell", to: "pull_requests/page_data/shared#copilot_code_review_dismiss_upsell", id: /\d+/, format: "json"
get "pull/:id/page_data/file_tree", to: "pull_requests/page_data/shared#file_tree", id: /\d+/, format: "json"
# TODO remove context_lines route when :react_diff_line_type_character_correction feature flag is graduated
get "pull/:id/page_data/context_lines", to: "pull_requests/page_data/shared#diff_entry_lines", id: /\d+/, format: "json"
get "pull/:id/page_data/diff_entry_lines", to: "pull_requests/page_data/shared#diff_entry_lines", id: /\d+/, format: "json"
get "pull/:id/page_data/diff_entries", to: "pull_requests/page_data/shared#diff_entries", id: /\d+/, format: "json"
get "pull/:id/page_data/codeowners", to: "pull_requests/page_data/shared#codeowners", id: /\d+/, format: "json"

# Header routes
get "/pull/:id/page_data/header", to: "pull_requests/page_data/shared#header", id: /\d+/, format: "json"
get "/pull/:id/page_data/code_button", to: "pull_requests/page_data/shared#code_button", id: /\d+/, format: "json"
get "/pull/:id/page_data/tab_counts", to: "pull_requests/page_data/shared#tab_counts", id: /\d+/, format: "json"
get "/pull/:id/page_data/diffstat", to: "pull_requests/page_data/shared#diffstat", id: /\d+/, format: "json"

# Mutations
patch "/pull/:id/page_data/change_base", to: "pull_requests/page_data/shared#change_base", id: /\d+/, format: "json"
post "/pull/:id/page_data/cleanup_codespaces", to: "pull_requests/page_data/mutations#cleanup_codespaces", id: /\d+/, format: "json"
post "/pull/:id/page_data/create_review_comment", to: "pull_requests/page_data/mutations#create_review_comment", id: /\d+/, format: "json"
patch "/pull/:id/page_data/update_title", to: "pull_requests/page_data/shared#update_title", id: /\d+/, format: "json"
put "/pull/:id/page_data/update_review_comment", to: "pull_requests/page_data/mutations#update_review_comment", id: /\d+/, format: "json"
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
put "/pull/:id/page_data/submit_review", to: "pull_requests/page_data/mutations#submit_review", id: /\d+/, format: "json"
delete "/pull/:id/page_data/abandon_review", to: "pull_requests/page_data/mutations#abandon_review", id: /\d+/, format: "json"
post "/pull/:id/page_data/resolve_thread", to: "pull_requests/page_data/mutations#resolve_thread", id: /\d+/, format: "json"
post "/pull/:id/page_data/unresolve_thread", to: "pull_requests/page_data/mutations#unresolve_thread", id: /\d+/, format: "json"
post "/pull/:id/page_data/hide_comment", to: "pull_requests/page_data/mutations#hide_comment", id: /\d+/, format: "json"
post "/pull/:id/page_data/unhide_comment", to: "pull_requests/page_data/mutations#unhide_comment", id: /\d+/, format: "json"
post "/pull/:id/page_data/apply_suggestions", to: "pull_requests/page_data/mutations#apply_suggestions", id: /\d+/, format: "json"
post "/pull/:id/page_data/run_action_required_workflows", to: "pull_requests/page_data/mutations#run_action_required_workflows", id: /\d+/, format: "json"
post "/pull/:id/page_data/update_merge_box_user_preference", to: "pull_requests/page_data/mutations#update_merge_box_user_preference", id: /\d+/, format: "json"
post "/pull/:id/page_data/add_comment_reaction", to: "pull_requests/page_data/mutations#add_comment_reaction", id: /\d+/, format: "json"
post "/pull/:id/page_data/remove_comment_reaction", to: "pull_requests/page_data/mutations#remove_comment_reaction", id: /\d+/, format: "json"
delete "/pull/:id/page_data/review_comments/:comment_id", to: "pull_requests/page_data/mutations#delete_review_comment", id: /\d+/, comment_id: /\d+/, format: "json"
