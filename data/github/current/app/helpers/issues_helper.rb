# typed: true
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module IssuesHelper
  extend T::Helpers
  include BranchesHelper
  include OcticonsHelper

  requires_ancestor { Object }

  LabelPlaceholder = Struct.new(:name, :color, :id, :name_html, :description)
  PULL_REQUESTS_TAG = "pull_requests"
  ISSUES_TAG = "issues"

  def current_repository
    super
  end

  # Generate href path to Issue.
  #
  # issue - Issue or PullRequest
  #
  # Returns String pathname.
  def issue_permalink_path(issue)
    T.bind(self, T.untyped)
    if issue.pull_request?
      pull_request_path(issue)
    else
      issue_path(issue)
    end
  end

  def original_discussion_for_created_issue(issue)
    if current_repository&.discussions_active?
      Discussion.for_repository(issue.repository).for_created_issue(issue).first
    end
  end

  def discussion_for_issue(issue)
    if current_repository&.discussions_active?
      Discussion.for_repository(issue.repository).converted_from_issue(issue).first
    end
  end

  def current_discussion_for_issue
    return unless defined?(current_issue)
    return @current_discussion_for_issue if defined?(@current_discussion_for_issue)
    @current_discussion_for_issue = discussion_for_issue(T.unsafe(self).current_issue)
  end

  def issue_page_description(issue)
    return nil if issue.body_text.nil?
    HTMLEntities.new.decode(T.unsafe(self).truncate(issue.body_text.squish, length: 240))
  end

  def show_issue_comment_box?
    return false if current_discussion_for_issue
    true
  end

  def can_modify_issue?(issue)
    return false unless T.unsafe(self).logged_in?
    return false if discussion_for_issue(issue)
    return true if issue.user == T.unsafe(self).current_user
    T.unsafe(self).current_user_can_push?
  end

  def milestone_percentage_tag(milestone)
    T.unsafe(self).content_tag :span, T.unsafe(self).number_to_percentage(milestone.progress_percentage.floor, precision: 0), class: "progress-percent"
  end

  def milestone_sort_label(sort, direction)
    case "#{sort}-#{direction}"
    when "due_date-asc"      then "Closest due date"
    when "due_date-desc"     then "Furthest due date"
    when "completeness-desc" then "Most complete"
    when "completeness-asc"  then "Least complete"
    when "title-asc"         then "Alphabetically"
    when "title-desc"        then "Reverse alphabetically"
    when "count-desc"        then "Most issues"
    when "count-asc"         then "Least issues"
    else "Recently updated"
    end
  end

  def label_sort(sort, direction)
    case "#{sort}-#{direction}"
    when "name-asc"   then "Alphabetically"
    when "name-desc"  then "Reverse alphabetically"
    when "count-desc" then "Most issues"
    when "count-asc"  then "Fewest issues"
    end
  end

  def issues_sort_menu_options
    [
      ["Newest", "created-desc"],
      ["Oldest", "created-asc"],
      ["Most commented", "comments-desc"],
      ["Least commented", "comments-asc"],
      ["Recently updated", "updated-desc"],
      ["Least recently updated", "updated-asc"],
      ["Best match", "relevance-desc"],
    ]
  end

  def issues_sort_labels
    {
      %w[created desc] => "Newest",
      %w[created asc]  => "Oldest",
      %w[comments desc] => "Most commented",
      %w[comments asc]  => "Least commented",
      %w[updated desc]  => "Recently updated",
      %w[updated asc]   => "Least recently updated",
      %w[relevance desc] => "Best match",
    }
  end

  # Issue page <title>. This is "Issues - <user>/<repo>" for index pages
  # or "<issue.title> - Issues - <user>/<repo>" for individual issue pages.
  def issue_page_title(issue = nil)
    [("#{issue.title} · Issue ##{issue.number}" if issue),
      ("Issues" if !issue),
      current_repository.name_with_display_owner,
    ].compact.join(" · ")
  end

  def milestone_due_text(milestone)
    T.bind(self, T.untyped)
    if milestone.closed?
      state = content_tag "strong" do
        "Closed "
      end
      safe_join [state, time_ago_in_words_js(milestone.closed_at)]
    elsif !milestone.due_on
      safe_join [" No due date"]
    elsif milestone.past_due?
      icon = content_tag(:span, octicon("alert"), class: "mr-1")
      content_tag(:strong,
        safe_join(
          [icon, " Past due by ", distance_of_time_in_words_to_now(milestone.due_date)],
        ),
        class: "description-warning",
        title: milestone.due_date.to_date.to_formatted_s(:long),
      )
    else
      icon = content_tag(:span, octicon("calendar"), class: "mr-1")
      safe_join [icon, " Due by ", milestone.due_date.to_date.to_formatted_s(:long)]
    end
  end

  def issues_search_term_values(search_key, excluded: false)
    T.unsafe(self).parsed_issues_query.select do |(key, _value, negation)|
      if negation && !excluded
        # search_key, if negated, is in the form "-term".
        # the equivalent parsed_query value would be [:"term", "value", true]
        # as such, we must prepend `key` with a `-` if negation is true to correctly match negated terms
        "-#{key}" == search_key.to_s
      elsif negation || excluded
        negation && excluded && key == search_key
      else
        key == search_key
      end
    end.map { |(_k, v)| v }
  end

  # calculates the urls we need when the user clicks on a label.
  # We'll go to the selected_url when the user left clicks. Additional labels are always
  # added to a new `label:` term in the query
  # We'll go to the excluded_url when the user option clicks. This will create a term like
  # `-label:one` in the query
  # We'll go to the included_url when the user shift clicks. This is intended to add labels
  # to an OR group, like `label:one,two,three` to the query
  def issue_label_data(filtered_labels, excluded_labels, pulls_only, label_name)
    selected = filtered_labels.include?(label_name)
    excluded = excluded_labels.include?(label_name)
    # [a, b, [c, d, e]]
    # label = d
    included = filtered_labels.find do |item|
      # 'included' labels are those whose value is an array instead of a string
      item.is_a?(Array) && item.include?(label_name)
    end
    # included = [c,d,e] | nil

    # selected, excluded, and included are truthy if the label
    # represented by label_name has previously been picked by the user.

    excluded_hash = { replace: {}, append: [], pulls_only: pulls_only }
    selected_hash = { replace: {}, append: [], pulls_only: pulls_only }
    included_hash = { replace: {}, append: [], pulls_only: pulls_only }

    # If this label has been picked but isn't part of an OR, we want
    # to remove it from the query when the user clicks on it
    if selected || excluded
      selected_hash[:replace] = { label: { label_name => nil } }
      excluded_hash[:replace] = { label: { label_name => nil } }
      included_hash[:replace] = { label: { label_name => nil } }
    end

    # If this label is part of an OR, we want to remove it from its
    # OR group when the user clicks on it.
    if included
      included_hash[:replace] = { label: { included => Array(included) - [label_name] } }
      selected_hash[:replace] = { label: { included => Array(included) - [label_name] } }
      excluded_hash[:replace] = { label: { included => Array(included) - [label_name] } }
    end

    if !selected && !excluded & !included
      # selecting always appends a new label filter
      selected_hash[:append] = [[:label, label_name]]

      # including will add the label to an existing filter if there is one
      # otherwise it'll append the label to a new filter
      last_filter = filtered_labels.last
      if last_filter
        included_hash[:replace] = { label: { last_filter => Array(last_filter) + [label_name] } }
      else
        included_hash[:append] = [[:label, label_name]]
      end
    end


    # if the users clicks this label, in addition to removing its positive form up above
    # we also want to add its negated from
    if !excluded
      excluded_hash[:append] = [[:label, label_name, true]]
    end

    selected_url = issues_search_query(**selected_hash)
    excluded_url = issues_search_query(**excluded_hash)
    included_url = issues_search_query(**included_hash)

    icon = if excluded
      "circle-slash"
    elsif included
      "dot-fill"
    else
      "check"
    end
    {
      selected_url: selected_url,
      included_url: included_url,
      excluded_url: excluded_url,
      selected: selected,
      included: included,
      excluded: excluded,
      icon: icon,
      checked: selected || excluded || !!included
    }
  end

  def issues_search_query(
    replace: {},
    append: [],
    pulls_only: false,
    repo_link: false,
    repo_name: nil,
    repo_owner_login: nil
  )
    components = T.unsafe(self).parsed_issues_query.dup

    replace.each_pair do |replace_key, replace_val|
      case replace_val
      when NilClass
        components.reject! { |comp_key, _| comp_key == replace_key }
      when Hash
        # Normally we use the 'replace' hash to remove selected filters. for instance
        # replace might look like {label: {"one" => nil}}
        # and components might look like [[:label, "one"]]
        components.reject! do |comp_key, comp_val|
          next unless comp_key == replace_key
          next unless replace_val.one?
          replace_val.keys.first == comp_val && replace_val.values.first.nil?
        end

        components.map! do |comp_key, comp_val|
          # In the case of an "or" syntax entry,
          # replace might look like  {label: {["one", "two", "three"] => ["one", "two"]}}
          # and components would look like [[:label, ["one", "two", "three"]]]
          # Here we truly want to replace the current component value with the new replace value
          should_replace = (comp_key == replace_key) &&
                            replace_val.one? &&
                            (replace_val.keys.first == comp_val)
          if should_replace
            [comp_key, replace_val[comp_val]]
          else
            [comp_key, comp_val]
          end
        end
      else
        components << [replace_key, replace_val]
      end
    end

    components += append

    if current_repository || repo_link
      if pulls_only
        return T.unsafe(self).pull_requests_path({
          q: Search::Queries::IssueQuery.stringify(components),
          repository: repo_link ? repo_name : nil,
          user_id: repo_link ? repo_owner_login : nil,
        }.compact)
      else
        return T.unsafe(self).issues_path({
          q: Search::Queries::IssueQuery.stringify(components),
          repository: repo_link ? repo_name : nil,
          user_id: repo_link ? repo_owner_login : nil,
        }.compact)
      end
    end

    if pulls_only
      T.unsafe(self).all_pulls_path(q: Search::Queries::IssueQuery.stringify(components))
    else
      T.unsafe(self).all_issues_path(q: Search::Queries::IssueQuery.stringify(components))
    end
  end

  def review_filter_menu_items
    terms = [
      ["No reviews", [[:review, "none"]]],
      ["Review required", [[:review, "required"]]],
      ["Approved review", [[:review, "approved"]]],
      ["Changes requested", [[:review, "changes-requested"]]],
    ]

    if T.unsafe(self).logged_in?
      search_param = Search::Query::MACRO_ME
      terms.concat([
        ["Reviewed by you", [[:"reviewed-by", search_param]]],
        ["Not reviewed by you", [[:"-reviewed-by", search_param]]],
      ])
      if current_repository&.owner&.organization?
        terms.concat([
          ["Awaiting review from you", [[:"user-review-requested", search_param]]],
          ["Awaiting review from you or your team", [[:"review-requested", search_param]]]
        ])
      else
        terms.concat([
          ["Awaiting review from you", [[:"user-review-requested", search_param]]],
        ])
      end
    end

    terms.map do |description, pairs|
      key = pairs.first.first
      values = pairs.map { |_key, value| value }
      selected = issues_search_term_values(key) == values
      url = issues_search_query(
        replace: { review: nil, "reviewed-by": nil, "-reviewed-by": nil, "review-requested": nil, "user-review-requested": nil },
        append: pairs,
        pulls_only: true,
      )
      { url: url, selected: selected, description: description }
    end
  end

  # These methods would be good candidates to move to a view model.
  # See https://github.com/github/github/pull/39990#issuecomment-86220009
  def showing_filtered_pulls?
    T.unsafe(self).parsed_issues_query != [[:is, "pr"], [:is, "open"]]
  end

  def showing_filtered_issues?
    T.unsafe(self).parsed_issues_query != [[:is, "issue"], [:is, "open"]]
  end

  def reaction_sort
    sort = T.unsafe(self).parsed_issues_query.select { |c| c.is_a?(Array) && c.first == :sort }.flatten.try(:second)
    return unless sort
    # sort looks like "reaction-+1-asc" here
    return unless sort.match(/reactions-(.*)-(desc|asc)/)
    $1
  end

  # Internal: Find issues matching query or ids
  #
  # BROKEN AND NEEDS TO BE REPLACED
  #
  # Returns an Array of Issues and total Integer count.
  def issues_triage_menu_find_issues(query)
    case query
    when String
      result = Search::Queries::IssueQuery.new({
        phrase: query,
        current_user: T.unsafe(self).current_user,
        repo_id: current_repository.id,
        per_page: 100,
        fields: [],
        normalizer: lambda { |results| results.map! { |h| h["_model"] }.compact },
        context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
      }).execute
      [result, result.total]
    when Array
      issues = current_repository.issues.where("issues.number IN (?)", query).to_a # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      [issues, issues.size]
    else
      [[], 0]
    end
  end

  # Public: Count how many milestones match the current search query.
  #
  # milestones - Array of Milestones
  # query      - String query or Array of issue IDs
  # &block
  #   milestone - Milestone in milestones
  #   count     - Integer count of milestones in issue query
  #   total     - Integer total number of milestones matching issue query
  #
  # Returns nothing.
  def issues_triage_menu_milestone_counts(milestones, query)
    # FIXME: Loads all Issue records into memory
    issues, total = issues_triage_menu_find_issues(query)

    # preload counts
    with_counts = {}
    milestones.each do |milestone|
      count = issues.count { |issue| issue.milestone_id == milestone.id }
      with_counts[milestone.id] = count
    end

    # selected items to the top
    milestones = milestones.partition do |milestone|
      with_counts[milestone.id] > 0
    end.flatten

    milestones.each do |milestone|
      yield milestone, with_counts[milestone.id], total
    end
  end

  # Public: Count how many assigned users match the current search query.
  #
  # users - Array of Users
  # query - String query or Array of issue IDs
  # &block
  #   user  - User in users
  #   count - Integer count of users in issue query
  #   total - Integer total number of users matching issue query
  #
  # Returns nothing.
  def issues_triage_menu_assignee_counts(users, query)
    issues, total = issues_triage_menu_find_issues(query)

    # preload assignment counts
    assignments = Assignment
      .select("assignee_id, COUNT(issue_id) AS assigned_count")
      .where(issue: issues)
      .group("assignee_id")
      .index_by(&:assignee_id)

    with_counts = users.each_with_object({}) do |user, hash|
      hash[user.login] = assignments[user.id]&.assigned_count.to_i
    end

    # selected items to the top
    users = users.partition do |user|
      with_counts[user.login] > 0
    end.flatten

    users.each do |user|
      yield user, with_counts[user.login], total
    end
  end

  # Public: Count how many labels match the current search query.
  #
  # labels - Array of Labels
  # query  - String query or Array of issue IDs
  # &block
  #   label - Label in labels
  #   count - Integer count of labels in issue query
  #   total - Integer total number of labels matching issue query
  #
  # Returns nothing.
  def issues_triage_menu_label_counts(labels, query)
    issues, total = issues_triage_menu_find_issues(query)

    results = Issue.connection.select_rows(Arel.sql(<<-SQL, issue_ids: issues.map(&:id)))
      SELECT label_id, COUNT(issue_id) AS labeled_count
      FROM issues_labels
      WHERE issue_id IN (:issue_ids)
      GROUP BY label_id
    SQL

    labeled = results.to_h

    with_counts = labels.each_with_object({}) do |label, hash|
      hash[label.name] = labeled[label.id].to_i
    end

    # selected items to the top
    labels = labels.partition do |label|
      with_counts[label.name] > 0
    end.flatten

    labels.each do |label|
      yield label, with_counts[label.name], total
    end
  end

  def issues_triage_menu_hidden_fields(issues)
    case issues
    when String
      field = T.unsafe(self).tag(:input,
        type: "hidden",
        name: "issues",
        value: issues,
      )
      T.unsafe(self).content_tag(:div, field, class: "js-issues-triage-fields")
    when Array
      fields = []
      issues.each do |number|
        fields << T.unsafe(self).tag(:input,
          type: "hidden",
          name: "issues[]",
          value: number,
        )
      end
      T.unsafe(self).content_tag(:div, T.unsafe(self).safe_join(fields), class: "js-issues-triage-fields")
    end
  end

  # Give me the task list link for this item.
  #
  # Returns a String.
  def task_list(object, include_left_margin: true)
    T.bind(self, T.untyped)
    content = "", classes = ""

    # shortcut complex link rendering when there are more than 100 task list items to prevent denial of service attacks
    # https://github.com/github/issues/issues/1979
    if object.has_too_many_tasks?
      content = octicon "checklist"
      content += content_tag(:span, "100+", class: "mx-1")
      return content_tag(:span, content, class: "d-inline-flex flex-row flex-items-center #{"ml-2" if include_left_margin}")
    end

    summary = TaskLists::SummaryView.new(object.async_lightweight_task_list_summary.sync)

    percent = number_to_percentage(((summary.complete_count / summary.item_count.to_f) * 100), precision: 0)

    content = "", classes = ""

    if object.is_a?(Issue) || object.is_a?(PullRequest)
      content = render Issues::TrackedIssuesProgressComponent.new(mode: :inline, completed: summary.complete_count, total: summary.item_count)
      classes = "d-inline-flex flex-row flex-items-center #{"ml-2" if include_left_margin}"
    else
      content = octicon "checklist"
      content += content_tag(:span, "#{summary.complete_count} of #{summary.item_count}", class: "task-progress-counts")
      content += content_tag(:span, content_tag(:span, "", class: "progress", style: "width: #{percent}"), class: "progress-bar v-align-middle")
      classes = "issue-meta-section task-progress #{"ml-2" if include_left_margin}"
    end

    content_tag(:span, content, class: classes)
  end

  def issue_thread_commentable?
    if !T.unsafe(self).logged_in?
      false
    elsif subject = @pull || @issue
      !subject.locked_for?(T.unsafe(self).current_user)
    else
      true
    end
  end

  def issue_show_partial_path(issue: nil, partial: nil, inline: nil, tasklist_id: nil)
    if issue.nil?
      T.unsafe(self).show_partial_new_issue_path(partial: partial)
    elsif issue.new_record?
      options = { partial: partial, issue: {} }
      options[:issue][:user_assignee_ids] = issue.assignees.map(&:id) if issue.assignees
      options[:issue][:milestone_id] = issue.milestone_id if issue.milestone
      options[:issue][:label_ids] = issue.label_ids if issue.label_ids.any?
      if issue.projects.any?
        options[:issue_project_ids] = Hash[issue.projects.map { |project| [project.id, "on"] }]
      end
      T.unsafe(self).show_partial_new_issue_path(options)
    else
      T.unsafe(self).show_partial_issue_path(id: issue.number, partial: partial, inline: inline, tasklist_id: tasklist_id)
    end
  end

  def modal_issues_login_path
    T.unsafe(self).login_path(return_to: T.unsafe(self).choose_issue_path)
  end

  def show_projects_ui?(repository)
    !repository.advisory_workspace? && (
      repository.projects_enabled? ||
      show_organization_projects_ui?(repository) ||
      show_user_projects_ui?(repository)
    )
  end

  def show_organization_projects_ui?(repository)
    repository.owner.organization? && repository.owner.organization_projects_enabled?
  end

  def show_user_projects_ui?(repository)
    repository.owner.user?
  end

  def show_labels_ui?(repository)
    !repository.advisory_workspace?
  end

  def show_milestones_ui?(repository)
    !repository.advisory_workspace?
  end

  def show_references_ui?(repository, issue = nil)
    return true if issue && issue.pull_request

    repository.has_issues? && !repository.advisory_workspace?
  end

  def memex_add_from_issue_triage_enabled?(repository)
    return unless show_projects_ui?(repository)
    GitHub.projects_new_enabled?
  end

  # Figure out the extra text for an issue close event
  #
  # Examples:
  #
  #   decafba
  #   user/repo@decafba
  #   #15
  #   user/repo#15
  #
  # Returns a String, or nil if there is no text to show
  def closer_reference_text(closed_event)
    identifier = if closed_event.closer.is_a?(PlatformTypes::Commit)
      closed_event.closer.abbreviated_oid
    else
      "##{closed_event.closer.number}"
    end

    if closed_event.closable.repository.id != closed_event.closer.repository.id
      T.unsafe(self).safe_join([
        closed_event.closer.repository.name_with_display_owner,
        closed_event.closer.is_a?(PlatformTypes::Commit) ? "@" : "",
        identifier,
      ])
    else
      identifier
    end
  end

  def find_card_for_sidebar(issue:, card_id:)
    issue.associated_cards(only_for_enabled_projects: true).find_by_id(card_id)
  end

  def issue_permissions(issue, actor, action, repository: nil)
    @issue_permissions ||= begin
      promises = async_issue_permissions(issue, actor, repository)
      labelable, assignable, milestoneable, closable, review_requestable, review_re_requestable, triageable, typeable = Promise.all(promises).sync

      {
        labelable: labelable,
        assignable: assignable,
        milestoneable: milestoneable,
        closable: closable,
        review_requestable: review_requestable,
        review_re_requestable: review_re_requestable,
        triageable: triageable,
        typeable: typeable,
      }
    end
    @issue_permissions[action]
  end

  def async_issue_permissions(issue, actor, repository = nil)
    promises = [
      issue.async_labelable_by?(actor: actor),
      issue.async_assignable_by?(actor: actor),
      issue.async_can_set_milestone?(actor),
    ]

    if issue.id
      promises << issue.async_closable_by?(actor)
    else
      promises << Promise.resolve(false)
    end

    if issue.pull_request?
      promises << issue.pull_request.async_can_request_review?(actor)
      promises << issue.pull_request.async_can_re_request_review?(actor)
    else
      promises += [Promise.resolve(false), Promise.resolve(false)]
    end

    promises << Promise.resolve(issue.triageable_by?(actor))

    if repository.present?
      promises << repository.async_owner.then do |owner|
        next false unless owner.issue_types_enabled?

        issue.async_can_set_type?(actor: actor)
      end
    else
      promises << Promise.resolve(false)
    end

    promises
  end

  def issue_pr_state_octicon(object, state, state_reason = nil)
    is_pull_request = if object.is_a?(Hovercard::Adapter::HovercardAdapter)
      object.is_pull_request?
    else
      object.is_a? PlatformTypes::PullRequest
    end

    if is_pull_request
      icon = PullRequest::Icon.new(
        object,
        permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues
      )
      octicon(
        icon.octicon_name,
        class: "#{icon.state} color-fg-#{icon.primer_color}",
        title: icon.short_label,
      )
    else
      if state == PlatformTypes::IssueState::OPEN
        octicon("issue-opened", class: "open color-fg-open", title: "Open")
      else
        if state_reason == "NOT_PLANNED"
          icon_info = Issue::StateReasonDependency::OCTICONS[:not_planned]
          octicon(icon_info[:icon], class: icon_info[:class], title: icon_info[:title])
        elsif state_reason == "DUPLICATE"
          icon_info = Issue::StateReasonDependency::OCTICONS[:duplicate]
          octicon(icon_info[:icon], class: icon_info[:class], title: icon_info[:title])
        else

          octicon("issue-closed", class: "closed color-fg-done", title: "Closed")
        end
      end
    end
  end

  def issue_pr_state_octicon_ar(object)
    if object.is_a? PullRequest
      icon = PullRequest::Icon.new(
        object,
        permit_queued_icon: false, # TODO: Remove this after resolving N+1 issues
      )
      octicon(
        icon.octicon_name,
        class: "#{icon.state} color-fg-#{icon.primer_color}",
        title: icon.short_label,
        "aria-label": icon.label,
      )
    else
      if object.open?
        octicon("issue-opened", class: "open", title: "Open", "aria-label": "Open issue")
      else
        if object.unplanned?
          not_planned_icon_info = Issue::StateReasonDependency::OCTICONS[:not_planned]
          octicon(not_planned_icon_info[:icon], class: not_planned_icon_info[:class], title: not_planned_icon_info[:title], "aria-label": not_planned_icon_info[:aria_label])
        else
          octicon("issue-closed", class: "closed", title: "Closed", "aria-label": "Closed issue")
        end
      end
    end
  end

  def blank_issue_hydro_tracking(user_id, repo_id)
    T.unsafe(self).hydro_click_tracking_attributes("blank_issue.click",
      actor_id: user_id,
      repository_id: repo_id,
      blank_issue_clicked: true,
    )
  end

  def linked_branches_for(issue:)
    # we sort in memory as the number of linked branches should be very low
    BranchIssueReference.viewable_by(user: T.unsafe(self).current_user, issue: issue)
  end

  def close_issue_references_for(issue_or_pr:, include_closed_prs: true, limit: nil)
    @close_issue_references = begin
      if issue_or_pr.is_a?(PullRequest)
        issue_or_pr.cap_filtered_close_issue_references_for(
          viewer: T.unsafe(self).current_user,
          cap_filter: T.unsafe(self).cap_filter)
      else
        issue_or_pr.cap_filtered_closed_by_pull_requests_references_for( # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          viewer: T.unsafe(self).current_user,
          cap_filter: T.unsafe(self).cap_filter,
          include_closed_prs: include_closed_prs,
          limit: limit)
      end
    end
  end

  def profile_names_for(user_ids:)
    Profile.where(user_id: user_ids.uniq).pluck(:user_id, :name).to_h
  end

  def render_layout?
    requested_no_layout = T.unsafe(self).params[:no_layout] == "1" && T.unsafe(self).logged_in? && T.unsafe(self).current_user.employee?
    !requested_no_layout
  end

  def force_layout?
    T.unsafe(self).params[:layout] == "1" && T.unsafe(self).logged_in? && T.unsafe(self).current_user.employee?
  end

  def render_repo_layout?
    requested_repo_layout = T.unsafe(self).params[:no_repo_layout] == "1" && T.unsafe(self).logged_in? && T.unsafe(self).current_user.employee?
    !requested_repo_layout
  end

  def render_content?
    requested_no_content = T.unsafe(self).params[:no_content] == "1" && T.unsafe(self).logged_in? && T.unsafe(self).current_user.employee?
    !requested_no_content
  end

  def create_issue_branch_name
    @create_issue_branch_name ||= BranchIssueReference.candidate_branch_name(issue: T.unsafe(self).current_issue)
  end

  # Allows sidebar content to be cached in session storage
  # cache_name must be a substring of the input name being cached
  def preserve_sidebar_attribute(cache_name:)
    "data-cacher data-cache-name=#{cache_name}"
  end
end
