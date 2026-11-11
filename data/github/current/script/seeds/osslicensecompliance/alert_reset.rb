# frozen_string_literal: true

# Cleanup script for local testing.
#
# Usage:
#   bin/rails runner script/seeds/osslicensecompliance/alert_reset.rb

require_relative "seed_helper"

abort "This script is intended to be run in a Codespace in development." unless running_on_localhost?
seed_context = setup_context
abort "Failed to set up context. Ensure the 2 required pull requests exist in http://github.localhost/github/public-server" if seed_context.nil?

# clear out alerts
alert_ids = (1..20).map(&:to_s)

puts "Resetting License Compliance artifacts for PR ##{seed_context.pull_request.number} (id=#{seed_context.pull_request.id}) in repo id=#{seed_context.repo.id}"
puts "Alert IDs: #{alert_ids.join(", ")}"

AutomatedReviewComment.transaction do
  automated_review_comments = AutomatedReviewComment.where(
    repository: seed_context.repo,
    pull_request: seed_context.pull_request,
    source: :source_license_compliance,
  )

  automated_review_comments = automated_review_comments.where(resource_id: alert_ids) if alert_ids.any?

  pull_request_review_comment_ids = automated_review_comments.pluck(:pull_request_review_comment_id).compact

  puts "Deleting AutomatedReviewComment rows: #{automated_review_comments.count}"
  automated_review_comments.find_each(&:destroy!)

  # AutomatedReviewComment points at PullRequestReviewComment via pull_request_review_comment_id.
  # Delete the PR review comments too so nothing remains visible in the PR UI.
  pr_review_comments = PullRequestReviewComment.where(
    pull_request_id: seed_context.pull_request.id,
    id: pull_request_review_comment_ids,
  )

  puts "Deleting PullRequestReviewComment rows: #{pr_review_comments.count}"
  pr_review_comments.find_each do |comment|
    result = PullRequests::ReviewComments::Delete.delete(
      repository: seed_context.repo,
      pull_request: seed_context.pull_request,
      actor: comment.user,
      comment: comment,
    )

    if result.is_a?(PullRequests::ReviewComments::Delete::Error)
      warn "Failed to delete PullRequestReviewComment id=#{comment.id}: #{result.errors.full_messages.join(", ")}"
    end
  end

  # Fallback: if for some reason the review comments exist but we can't find the corresponding
  # AutomatedReviewComment rows (e.g., they were deleted separately), delete the PR review comments
  # by heuristics (author + body marker).
  if pull_request_review_comment_ids.empty?
    bot = Apps::Privileged.attribution_only_system_identity_for(:license_compliance)
    if bot
      heuristic_comments = PullRequestReviewComment.where(pull_request_id: seed_context.pull_request.id, user_id: bot.id)
        .where("body LIKE ?", "%security/license-compliance%")

      puts "Deleting PullRequestReviewComment fallback rows: #{heuristic_comments.count}"
      heuristic_comments.find_each do |comment|
        result = PullRequests::ReviewComments::Delete.delete(
          repository: seed_context.repo,
          pull_request: seed_context.pull_request,
          actor: comment.user,
          comment: comment,
        )

        if result.is_a?(PullRequests::ReviewComments::Delete::Error)
          warn "Failed to delete PullRequestReviewComment id=#{comment.id}: #{result.errors.full_messages.join(", ")}"
        end
      end
    end
  end

  # If you also exercised the Hydro processor path, it can create/update license compliance dismissal requests.
  exemption_requests = Exemptions::ExemptionRequest.where(
    request_type: "license_compliance_dismissal",
    resource_owner: seed_context.repo,
    resource_identifier: alert_ids,
  )

  exemption_responses = Exemptions::ExemptionResponse.where(exemption_request_id: exemption_requests.select(:id))

  puts "Deleting Exemptions::ExemptionResponse rows: #{exemption_responses.count}"
  exemption_responses.find_each(&:destroy!)

  puts "Deleting Exemptions::ExemptionRequest rows: #{exemption_requests.count}"
  exemption_requests.find_each(&:destroy!)
end

puts "Done."
