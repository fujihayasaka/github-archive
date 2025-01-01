# typed: strict
# frozen_string_literal: true

# Uses a large language model to generate a summary of an issue and a portion of
# its timeline events, such as its comments.
class IssueSummarizeJob < ApplicationJob
  STATS_KEY = "issue_summarize"

  queue_as :issue_summarize

  # Ensures that only one job is running for a given issue at a time.
  locked_by timeout: 1.hour, key: ->(job) {
    job.arguments[0]
  }

  # Safe to retry: It is okay to overwrite existing issue summaries.
  retry_on_dirty_exit

  before_enqueue { GitHub.dogstats.increment("#{STATS_KEY}.enqueue") }
  before_perform { GitHub.dogstats.increment("#{STATS_KEY}.perform") }

  sig { params(issue_summary_id: Integer, options: T::Hash[Symbol, T.nilable(String)]).void }
  def perform(issue_summary_id, options = { api_key: nil })
    issue_summary = IssueSummary.find_by(id: issue_summary_id)

    unless issue_summary
      # Issue summary was deleted (or replication lag?)
      GitHub.dogstats.increment(STATS_KEY, tags: ["found-summary:false"])
      return
    end

    begin
      ActiveRecord::Base.connected_to(role: :writing) do
        issue_summary.transition_in_progress!
      end

      issue = issue_summary.issue
      user = issue_summary.user

      unless issue
        # Issue was deleted (or replication lag?)
        GitHub.dogstats.increment(STATS_KEY, tags: ["found-issue:false"])
        return
      end

      unless user
        # User was deleted?
        GitHub.dogstats.increment(STATS_KEY, tags: ["found-user:false"])
        return
      end
      # TODO: Update the job and tests for the following using CAPI REST endpoints
      prompt = IssueSummarizeJob.prompt_for(issue_summary)
      response = user.copilot_api(integration_id: CopilotAPI::COPILOT_4_PRS_INTEGRATION_ID).create_completion(
        prompt: prompt,
        model: "cushman-ml-ppe08-centralus-b",
        max_tokens: 256,
        temperature: 0.5
      )
      if response.error.present?
        GitHub.dogstats.increment(STATS_KEY, tags: ["found:true", "error:true"])

        ActiveRecord::Base.connected_to(role: :writing) do
          issue_summary.transition_failed!
        end
      else
        GitHub.dogstats.increment(STATS_KEY, tags: ["found:true", "error:false"])

        summary = response.data&.text || ""

        ActiveRecord::Base.connected_to(role: :writing) do
          issue_summary.update!(content: summary)
          issue_summary.transition_complete!
        end
      end

    rescue # rubocop:disable Lint/RescueException
      # We want to always log the exception stat and mark the summarization as
      # failed.
      GitHub.dogstats.increment(STATS_KEY, tags: ["exception:true"])

      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          issue_summary.transition_failed!
        # In case content was set to an invalid value
        rescue # rubocop:disable Lint/RescueException
          existing_issue_summary = IssueSummary.find(issue_summary.id)
          existing_issue_summary.transition_failed!
        end
      end

      raise
    end
  end

  sig { params(issue_summary: IssueSummary).returns(String) }
  def self.prompt_for(issue_summary)

    issue = T.must(issue_summary.issue)
    user_name = T.must(issue_summary.user).display_login

    prompt = <<~PROMPT
    My name is @#{user_name}.
    @#{T.must(issue.user).display_login} created a GitHub issue with the following title and description:

    Title: '''#{issue.title}'''
    Description: '''#{issue.body}'''

    #{render_timeline(issue)}
    PROMPT

    prompt
  end

  sig { params(issue: Issue).returns(String) }
  def self.render_timeline(issue)
    context = Issue::Adapter::Context.new(
      issue,
      issue.repository,
      T.must(issue.repository).owner
    )

    timeline_loader = Issue::Loader::IssueTimeline.new(context, {})
    timeline_entries = timeline_loader.timeline_entries

    prompt = ""
    if timeline_entries.empty?
      prompt = "Please summarize the issue as short as possible."
    else
      post_prompt = <<~PROMPT

      Please summarize the issue and responses as short as possible.
      You may use additional paragraphs if there are many different viewpoints represented. When summarizing, it is important to @-mention the author of the content you're currently summarizing (for example, "@user writes that...").
      Do not add any additional comments.
      PROMPT

      result = []

      timeline_entries.each do |entry|
        if entry.instance_of? IssueComment
          result << "@#{User.find(entry.user_id).display_login} commented: '#{entry.compressed_body}'"
        end

        if entry.instance_of? IssueEvent
          event_prompt = prompt_for_event(entry.event)
          unless event_prompt.nil?
            result << "@#{User.find(entry.actor_id).display_login} #{event_prompt}"
          end
        end

      end

      result << post_prompt
      result.join("\n")
    end
  end

  sig { params(event: String).returns(T.nilable(String)) }
  def self.prompt_for_event(event)
    mappings = {
      "closed" => "closed the issue",
      "reopened" => "reopened the issue",
      "merged" => nil,
      "referenced" => nil,
      "labeled" => nil,
      "unlabeled" => nil,
      "assigned" => nil,
      "unassigned" => nil,
      "milestoned" => nil,
      "demilestoned" => nil,
      "locked" => "locked the issue",
      "unlocked" => "unlocked the issue",
      "renamed" => "renamed the issue",
      "deployed" => nil,
      "deployment_environment_changed" => nil,
      "head_ref_deleted" => nil,
      "head_ref_restored" => nil,
      "base_ref_force_pushed" => nil,
      "head_ref_force_pushed" => nil,
      "base_ref_changed" => nil,
      "base_ref_deleted" => nil,
      "automatic_base_change_succeeded" => nil,
      "automatic_base_change_failed" => nil,
      "added_to_merge_queue" => nil,
      "removed_from_merge_queue" => nil,
      "ready_for_review" => nil,
      "review_dismissed" => nil,
      "review_requested" => nil,
      "review_request_removed" => nil,
      "convert_to_draft" => nil,
      "added_to_project" => nil,
      "moved_columns_in_project" => nil,
      "removed_from_project" => nil,
      "converted_note_to_issue" => nil,
      "comment_deleted" => nil,
      "marked_as_duplicate" => "marked the issue as a duplicate",
      "unmarked_as_duplicate" => "unmarked the issue as a duplicate",
      "transferred" => nil,
      "pinned" => "pinned the issue",
      "unpinned" => "unpinned the issue",
      "user_blocked" => nil,
      "connected" => nil,
      "disconnected" => nil,
      "auto_merge_enabled" => nil,
      "auto_rebase_enabled" => nil,
      "auto_squash_enabled" => nil,
      "auto_merge_disabled" => nil,
      "converted_to_discussion" => nil,
    }

    mappings[event]
  end

  # Enqueues a new job to summarize the given issue.
  sig do
    params(issue_summary: IssueSummary, options: T::Hash[Symbol, T.untyped])
      .returns(T.any(IssueSummarizeJob, FalseClass))
  end
  def self.enqueue(issue_summary, options = { api_key: nil })
    IssueSummarizeJob.perform_later(issue_summary.id, options)
  end
end
