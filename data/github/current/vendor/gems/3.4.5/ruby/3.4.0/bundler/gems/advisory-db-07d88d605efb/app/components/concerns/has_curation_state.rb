# frozen_string_literal: true

module HasCurationState
  def curation_state_icon(curation_state)
    case curation_state
    when "in_triage" then "inbox"
    when "waiting" then "waiting"
    when "open" then "issue-opened"
    when "open_create" then "open-new"
    when "open_update" then "issue-reopened"
    when "ready" then "codescan"
    when "ready_to_publish" then "codescan-checkmark"
    when "ready_to_withdraw" then "ready-withdraw"
    when "published" then "check-circle"
    when "published_reviewed" then "verified"
    when "published_unreviewed" then "published-unreviewed"
    when "rejected", "withdrawn" then "no-entry"
    when "closed" then "x-circle"
    else "question"
    end
  end

  def curation_state_color(curation_state)
    case curation_state
    when "in_triage", "waiting" then :muted
    when "open_create", "open_update", "open" then :success
    when "ready_to_publish", "ready_to_withdraw", "ready" then :attention
    when "published", "published_reviewed", "published_unreviewed" then :done
    when "closed", "withdrawn", "rejected" then :danger
    else :accent
    end
  end

  def curation_state_scheme(curation_state)
    case curation_state
    when "in_triage", "waiting" then :default
    when "open_create", "open_update", "open", "ready_to_publish", "ready_to_withdraw" then :open
    when "published", "published_reviewed", "published_unreviewed" then :merged
    when "closed", "withdrawn", "rejected" then :closed
    end
  end

  def curation_state_label(curation_state)
    case curation_state
    when "closed" then "Closed"
    when "in_triage" then "Triage"
    when "waiting" then "Waiting"
    when "open" then "Open"
    when "open_create" then "Open - New"
    when "open_update" then "Open - Update"
    when "ready" then "Ready"
    when "ready_to_publish" then "Ready to Publish"
    when "ready_to_withdraw" then "Ready to Withdraw"
    when "published" then "Published"
    when "published_reviewed" then "Published - Reviewed"
    when "published_unreviewed" then "Published - Unreviewed"
    when "rejected" then "Published - Rejected"
    when "withdrawn" then "Withdrawn"
    when "all" then "All"
    else "Unknown"
    end
  end
end
