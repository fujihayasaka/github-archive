# typed: strict
# frozen_string_literal: true

# A human-readable summary of an issue and portions of its timeline events.
class IssueSummary < ApplicationRecord::Domain::UsersBallast
  include State

  belongs_to :issue
  belongs_to :user

  after_initialize :set_initial_state, if: :new_record?
  after_create :enqueue_summarization # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_create :send_issue_alive_update # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_save :send_alive_update # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  sig { void }
  def reset_and_schedule
    set_initial_state
    enqueue_summarization
  end

  sig { void }
  private def set_initial_state
    self.state = State.initial_state
    self.content = ""
  end

  sig { void }
  private def send_alive_update
    channel_id = GitHub::WebSocket::Channels.issue_summary(self)
    GitHub::WebSocket.notify_issue_summary_channel(self, channel_id)
  end

  sig { void }
  private def send_issue_alive_update
    channel_id = GitHub::WebSocket::Channels.issue(self.issue)
    GitHub::WebSocket.notify_issue_summary_channel(self, channel_id)
  end

  sig { returns(T.any(IssueSummarizeJob, FalseClass)) }
  private def enqueue_summarization
    transition_scheduled!
    IssueSummarizeJob.enqueue(self, {})
  end
end
