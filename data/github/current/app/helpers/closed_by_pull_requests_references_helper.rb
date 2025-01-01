# typed: true
# frozen_string_literal: true

module ClosedByPullRequestsReferencesHelper
  extend T::Helpers

  requires_ancestor { ActionView::Helpers::TagHelper }
  requires_ancestor { IssuesHelper }
  requires_ancestor { HovercardHelper }
  requires_ancestor { HydroHelper }

  def issue_xrefs_html(issue, reference_location)
    pull_requests = close_issue_references_for(issue_or_pr: issue, include_closed_prs: false, limit: 10).take(5)

    if pull_requests.any?
      merged_prs, open_prs = pull_requests.partition { |pr| pr.merged? }

      merged_pr_text = merged_pr_text(issue, reference_location, merged_prs) || ""
      open_pr_text = open_pr_text(issue, reference_location, merged_prs, open_prs) || ""
      content_tag(:span, safe_join([content_tag(:span, merged_pr_text), content_tag(:span, open_pr_text)]))
    end
  end

  def format_references(issue, reference_location, pulls)
    pulls.map do |pull|
      reference = if issue.repository.name_with_owner == pull.repository.name_with_owner
        "##{pull.number}"
      else
        "#{pull.repository.name_with_display_owner}##{pull.number}"
      end
      # add hydro attributes and hovercard attributes to links
      # hovercards only appear when `data-issue-and-pr-hovercards-enabled` attribute is on containing div
      data = xrefs_hydro_attributes(issue_id: issue.id, pull_request_id: pull.id, reference_location: reference_location)
      data.merge!(hovercard_data_attributes_for_issue_or_pr(pull))
      content_tag(:a, href: pull.url.to_s, data: data) do
        reference
      end
    end
  end

  def xrefs_hydro_attributes(issue_id:, pull_request_id:, reference_location:)
    hydro_click_tracking_attributes("issue_cross_references.click",
      reference_location: reference_location,
      user_id: GitHub.context[:actor_id],
      issue_id: issue_id,
      pull_request_id: pull_request_id,
    )
  end

  def merged_pr_text(issue, reference_location, merged_prs)
    if merged_prs.any?
      references = format_references(issue, reference_location, merged_prs)
      merged_prs_links = to_sentence(references, two_words_connector: " or ", last_word_connector: " or ")
      safe_join([" · Fixed by ", merged_prs_links], "")
    end
  end

  def open_pr_text(issue, reference_location, merged_prs, open_prs)
    if merged_prs.any? && open_prs.count > 3
      " · #{open_prs.count} remaining pull requests "
    elsif open_prs.any?
      references = format_references(issue, reference_location, open_prs)
      open_prs_links = to_sentence(references, two_words_connector: " or ", last_word_connector: " or ")
      safe_join([" · May be fixed by ", open_prs_links], "")
    end
  end
end
