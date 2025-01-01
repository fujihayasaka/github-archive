# typed: true
# frozen_string_literal: true

class PinnedIssue < ApplicationRecord::Collab
  include GitHub::Relay::GlobalIdentification

  belongs_to :repository
  belongs_to :pinned_by, class_name: "User"
  belongs_to :issue

  validates :issue_id, uniqueness: true

  after_create_commit :generate_pinned_event # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  def generate_unpinned_event(actor:)
    T.must(issue).instrument(:unpinned, actor: actor, event: "unpinned")
    GlobalInstrumenter.instrument("issue.unpinned", { repository: repository, actor: actor, state: "UNPINNED", issue: issue })
    T.must(issue).events.create!(actor: actor, event: "unpinned")
  end

  private

  def generate_pinned_event
    T.must(issue).instrument(:pinned, actor: pinned_by, event: "pinned")
    GlobalInstrumenter.instrument("issue.pinned", { repository: repository, actor: pinned_by, state: "PINNED", issue: issue })
    T.must(issue).events.create!(actor: pinned_by, event: "pinned")
  end
end
