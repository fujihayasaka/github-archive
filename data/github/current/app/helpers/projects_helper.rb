# typed: false
# frozen_string_literal: true

module ProjectsHelper
  include PlatformHelper

  DEFAULT_SORT = "created-desc"
  SORTS = [
             ["Newest", "created-desc"],
             ["Oldest", "created-asc"],
             ["Recently updated", "updated-desc"],
             ["Least recently updated", "updated-asc"],
             ["Name", "name-asc"],
          ].freeze

  def card_movable?(card)
    return false if card.project.closed?
    !card.redacted? && card.project.writable_by?(current_user)
  end

  def card_menu(card, &block)
    if card.persisted?
      render partial: "projects/card_menu", locals: { card: card, capture: capture(&block) }
    end
  end

  def enable_dragging?(project)
    return false if project.closed?
    if project.is_a?(PlatformTypes::Updatable)
      project.viewer_can_update?
    else
      project.writable_by?(current_user)
    end
  end

  def issue_label(issue)
    if issue.state == "locked"
      "Locked Issue"
    elsif issue.pull_request
      "Pull Request"
    elsif issue.open?
      "Open Issue"
    elsif issue.state_reason_not_planned? || issue.state_reason_duplicate?
      Issue::StateReasonDependency::OCTICONS[:not_planned][:aria_label]
    else
      "Closed Issue"
    end
  end

  def issue_icon(issue)
    if issue.state == "locked"
      "lock"
    elsif issue.pull_request?
      PullRequest::Icon.new(
        issue.pull_request,
        permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues
      ).octicon_name
    elsif issue.open?
      "issue-opened"
    elsif issue.state_reason_not_planned? || issue.state_reason_duplicate?
      Issue::StateReasonDependency::OCTICONS[:not_planned][:icon]
    else
      "issue-closed"
    end
  end

  def issue_class(issue)
    if issue.pull_request?
      PullRequest::Icon.new(
        issue.pull_request,
        permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues
      ).state
    elsif issue.open?
      "open"
    elsif issue.state_reason_not_planned? || issue.state_reason_duplicate?
      Issue::StateReasonDependency::OCTICONS[:not_planned][:class]
    else
      "closed"
    end
  end

  def redacted_card_icon(reason_for_redaction)
    if reason_for_redaction == :repository_missing
      "circle-slash"
    elsif reason_for_redaction == :unauthorized
      "shield-lock"
    else
      "lock"
    end
  end

  def redacted_card_title(reason_for_redaction)
    if reason_for_redaction == :repository_missing
      "Card content unavailable"
    else
      "You can't see this card"
    end
  end

  def redacted_card_message(reason_for_redaction)
    if reason_for_redaction == :spammy
      "This card references something that has spammy content."
    elsif reason_for_redaction == :repository_missing
      "This card references something in a repository that was deleted."
    elsif reason_for_redaction == :issue_missing
      "This card references a deleted issue."
    else
      "This card references something you don't have access to."
    end
  end

  # Returns a friendly list of automation purposes for all columns
  # Requires an array of pre-fetched ProjectColumns from GraphQL
  #
  def automation_summary(column_purposes)
    purposes = column_purposes.compact
    purposes.map do |purpose|
      if purpose == "TODO"
        "To do"
      else
        purpose.humanize
      end
    end.uniq.to_sentence
  end

  def clone_settings_summary(workflow_count)
    settings = ["column names", "positions"]
    settings << "automation settings" if workflow_count > 0
    settings.to_sentence
  end

  def cloneable_name(project_name)
    "[COPY] #{project_name}".truncate(Project::MAX_NAME_LENGTH, omission: "")
  end

  def is_account_project?(project)
    %w[Organization User].include?(project.owner_type)
  end

  # Default query for use on the "Add Cards" search pane
  #
  def default_card_search_value
    "is:open"
  end

  def projects_search_term_values(key)
    parsed_projects_query.select { |(k, _v)| k == key }.map { |(_k, v)| v }
  end

  # creates a new search query by duplicating the current parsed query and then
  # applies any of the arguments to said duplicate
  def projects_search_query(replace: {}, append: [], remove: {})
    components = parsed_projects_query.dup

    replace.each_pair do |key, value|
      if value
        components << [key, value]
      else
        components.reject! { |k, _v| k == key }
      end
    end

    components.delete_if do |_key, value|
      remove.value?(value)
    end

    components += append
    Search::Queries::ProjectQuery.stringify(components)
  end

  def format_search_query(query)
    if query.present?
      "#{query.rstrip} "
    elsif defined?(project_index_query)
      "#{project_index_query} "
    else
      ""
    end
  end

  def filtered_project_sorts
    projects_search_term_values(:sort)[0] || DEFAULT_SORT
  end

  def selected_project_sort?(sort)
    filtered_project_sorts == sort
  end

  def hide_project?(state_filter, project_state)
    return false unless state_filter.present?
    return false unless state_filter == "open" || state_filter == "closed"
    state_filter.upcase != project_state
  end

  def showing_filtered_projects?
    parsed_projects_query != [[:is, "open"]]
  end

  def search_includes_name?
    # look for a user supplied string
    # :sort and :is queries will be an array in the parsed query
    parsed_projects_query.any? { |component| component.is_a?(String) }
  end

  # Truncate the project body markdown to just the first paragraph
  def truncate_project_body_markdown(markdown_html)
    doc = Nokogiri::HTML::DocumentFragment.parse(markdown_html)

    first_paragraph = doc.at("p")
    return unless first_paragraph

    # Don't truncate if the entire document is one single paragraph
    return if first_paragraph == doc.first_element_child && doc.element_children.length == 1

    html = first_paragraph.inner_html
    html = content_tag(:span, html, nil, false) if markdown_html.html_safe?
    html
  end

  def project_body_markdown(body)
    markdown_html = github_simplified_markdown(body)
    truncated_markdown_html = truncate_project_body_markdown(markdown_html)
    yield markdown_html, truncated_markdown_html
  end

  def column_purpose_options
    {
      nil => { name: "None", description: "This column will not be automated" },
      "TODO" => { name: "To do", description: "Planned but not started" },
      "IN_PROGRESS" => { name: "In progress", description: "Actively being worked on" },
      "DONE" => { name: "Done", description: "Items are complete" },
    }
  end

  def column_purpose_name(purpose_value)
    column_purpose_options[purpose_value][:name]
  end

  def include_staff_bar(view_id:)
    return unless staff_bar_enabled?

    if params[:xhr_stats].present? && !request.xhr?
      render partial: "projects/staff_bar"
    else
      render partial: "stafftools/staffbar/stats", locals: {
        view: Stafftools::Staffbar::ProjectStats.new(request: request, element_id_suffix: "-#{view_id}"),
      }
    end
  end

  def project_column_anchor_url(project_column)
    # HACK: Sorbet does not know that `ProjectColumnAnchorUrl` is a `Module`,
    # so a static reference to `ProjectColumnAnchorUrl::ProjectColumn` is
    # considered an error. Since we are removing GraphQL from the view layer
    # anyway, let's just trick Sorbet for now by using a dynamic reference.
    project_column = ProjectColumnAnchorUrl.const_get("ProjectColumn").new(project_column)
    "#{project_column.project.url}#column-#{project_column.database_id}"
  end

  # Should dragging columns and cards be limited to only a specific dragging
  # handle instead being able to drag by the entire card/column element?
  #
  # On phone/tablet touch devices a dragging handle should be used so that
  # the scroll events can be distinguished from drag events.
  def enable_drag_by_handle?
    return true if mobile?

    # Also enable drag by handle on iPads and Android tablets
    request.user_agent.to_s =~ /iPad;|Android/
  end

  def wrap_projects_page_info(page_info)
    ProjectsCursorPaginate.new(page_info)
  end

  def previous_projects_cursor_url(page_info)
    page_info = wrap_projects_page_info(page_info)
    previous_url = projects_cursor_pagination_params
    previous_url[:before] = page_info.start_cursor
    safe_url_for(previous_url)
  end

  def next_projects_cursor_url(page_info)
    page_info = wrap_projects_page_info(page_info)
    next_url = projects_cursor_pagination_params
    next_url[:after] = page_info.end_cursor
    safe_url_for(next_url)
  end

  def projects_cursor_paginate(page_info, previous_label:, next_label:)
    page_info = wrap_projects_page_info(page_info)
    links = []

    link_attrs = { rel: "nofollow", class: "btn BtnGroup-item" }

    if page_info.has_previous_page?
      previous_url = previous_projects_cursor_url(page_info)

      links << link_to(previous_label, previous_url, link_attrs)
    else
      links << content_tag(:button, previous_label, { class: "btn BtnGroup-item", disabled: true })
    end

    if page_info.has_next_page?
      next_url = next_projects_cursor_url(page_info)

      links << link_to(next_label, next_url, link_attrs)
    else
      links << content_tag(:button, next_label, { class: "btn BtnGroup-item", disabled: true })
    end

    content_tag :div, safe_join(links), { class: "BtnGroup", "data-test-selector": "pagination" }
  end

  def projects_cursor_pagination_params
    # remove existing cursor params
    cursor_params = params.dup.permit!.to_hash.with_indifferent_access.except(:before, :after)
  end
end
