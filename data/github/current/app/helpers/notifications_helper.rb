# typed: true
# frozen_string_literal: true

module NotificationsHelper
  extend T::Helpers
  include OcticonsHelper

  def paginate_subscriptions(total_count, options = {})
    # since sorbet cannot find subscriptions_page, we need to add T.bind(self, T.untyped) to disable type checking
    T.bind(self, T.untyped).subscriptions_page
    raw_paginate total_count.to_i, NotificationsController::SUBSCRIPTIONS_PER_PAGE, subscriptions_page, options
  end

  def notification_octicon_for(subject, classes: "")
    case subject
    when ::Commit
      octicon("git-commit", class: classes)
    when ::Issue
      case subject.state.to_s.upcase
      when "OPEN"
        octicon("issue-opened", class: classes + " color-fg-open")
      when "CLOSED"
        if subject.state_reason.to_s.upcase == "NOT_PLANNED"
          icon_info = Issue::StateReasonDependency::OCTICONS[:not_planned]
          octicon(icon_info[:icon], class: classes + icon_info[:class], title: icon_info[:title])
        elsif subject.state_reason.to_s.upcase == "DUPLICATE"
          icon_info = Issue::StateReasonDependency::OCTICONS[:duplicate]
          octicon(icon_info[:icon], class: classes + icon_info[:class], title: icon_info[:title])
        else
          octicon("issue-closed", class: classes + " color-fg-done")
        end
      end
    when ::PullRequest
      icon = ::PullRequest::Icon.new(
        subject,
        permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues
      )
      octicon(
        icon.octicon_name,
        class: classes + " color-fg-#{icon.primer_color}",
      )
    when ::Release
      octicon("tag", class: classes)
    when ::RepositoryInvitation
      octicon("mail", class: classes)
    when ::RepositoryVulnerabilityAlert, ::SecurityAdvisory, ::RepositoryDependabotAlertsThread
      octicon("alert", class: classes)
    when ::DiscussionPost
      octicon("comment-discussion", class: classes)
    when ::Discussion
      T.bind(self, DiscussionsHelper)
      discussion_icon(subject)
    when ::RepositoryAdvisory
      state = subject.state.to_s.upcase
      icon =
        case state
        when "CLOSED" then "shield-x"
        when "PUBLISHED" then "shield-check"
        else "shield"
        end
      color = notification_icon_color_for(state, state == "OPEN")
      octicon(icon, class: "#{classes} #{color}")
    when ::AdvisoryCredit
      color = notification_icon_color_for(subject.state, false)
      octicon("shield", class: "#{classes} #{color}")
    when ::Gist
      octicon("code", class: classes)
    when Actions::WorkflowRun
      octicon("rocket", class: "#{classes} #{color}")
    when ::MemexProject
      octicon("table", class: classes)
    end
  end

  def notification_icon_color_for(state, is_draft = false)
    case state.to_s.upcase
    when "OPEN", "ACCEPTED", "PUBLISHED"
      if is_draft
        "color-fg-muted"
      else
        "color-fg-open"
      end
    when "CLOSED", "DECLINED"
      "color-fg-closed"
    when "MERGED"
      "color-fg-done"
    when "PENDING"
      "color-fg-attention"
    end
  end

  def notification_reason_label(enum_reason)
    case enum_reason.upcase
    when "ASSIGN"
      "assigned"
    when "COMMENT"
      "commented"
    else
      enum_reason.humanize(capitalize: false)
    end
  end
end
