# typed: true
# frozen_string_literal: true

class MemexProjectItemPrefiller
  include GitHub::Tracing
  include MemexProjectColumnValue::ReviewerHashable
  include Scientist

  # How many IDs should be in a SQL `IN` clause at a time? Trying to balance between number of queries run and
  # limiting the length of `IN` clauses because large ones result in slow queries.
  IN_CLAUSE_BATCH_SIZE = 250

  trace_method(
    :prefill,
    span_attribute_extractor: ->(prefiller, *_args, **__kwargs) do
      field_counts = MemexPerformanceStatsHelper.column_count_by_type(
        prefiller.columns,
        key_prefix: "gh.memex.prefiller.field_count."
      )

      {
        "gh.memex.prefiller.height" => prefiller.items.length,
        "gh.memex.prefiller.height_bucket" => MemexPerformanceStatsHelper.height_bucket(prefiller.items.length),
        "gh.memex.prefiller.width" => prefiller.columns.length,
        "gh.memex.prefiller.width_bucket" => MemexPerformanceStatsHelper.width_bucket(prefiller.columns.length),
        "gh.memex.prefiller.read_denormalized_title" => prefiller.read_denormalized_title,
        "gh.memex.prefiller.read_denormalized_milestone" => prefiller.read_denormalized_milestone,
        "gh.memex.prefiller.add_item_id_clause_to_column_values_query" => prefiller.add_item_id_clause_to_column_values_query,
      }.merge(field_counts)
    end,
    span_annotator: ->(prefiller, span, _context, _result) do
      # We add this attribute after the method call so that `prefiller.items`, which might be a scope,
      # has already been materialized.
      if memex_project_id = prefiller.items.first&.memex_project_id
        span.add_attributes({ "gh.memex.project_id" => memex_project_id })
      end
    end
  )

  trace_method(:fill_memex_project_column_values)
  trace_method(:fill_memex_labels)
  trace_method(:fill_memex_issue_types)
  trace_method(:fill_memex_parent_issues)
  trace_method(:fill_memex_linked_pull_requests)
  trace_method(:fill_memex_items_completion)
  trace_method(:fill_memex_tracked_by_items)
  trace_method(:fill_memex_milestones)
  trace_method(:fill_memex_repositories)
  trace_method(:fill_memex_assignees)
  trace_method(:fill_memex_reviewers)
  trace_method(:fill_draft_issue_assignees)
  trace_method(:fill_primary_avatars)
  trace_method(:fill_sub_issues_progress)

  attr_reader :items, :columns, :read_denormalized_title, :read_denormalized_milestone,
    :add_item_id_clause_to_column_values_query

  # Params:
  #
  #   items - Array<MemexProjectItem>, the items to prefill associations on.
  #     These must all come from the same MemexProject.
  #   columns - Array<MemexProjectColumn>, the columns that the caller intends
  #     to serialize. Where possible, we'll avoid prefilling some associations
  #     if we know the caller doesn't need them.
  #   read_denormalized_title - Whether or not to load data more efficiently by
  #     reading from the denormalized source for content titles and metadata.
  #   title_column - The title column of the items' MemexProject. This must be
  #     provided if `read_denormalized_title` is true.
  #   read_denormalized_milestone - Whether or not to read the
  #     denormalized values for the milestones associated with the items.
  #   add_item_id_clause_to_column_values_query - Whether or not to add an IN clause for item IDs to the query against
  #     `memex_project_column_values`. See inline comment where this is used for more details.
  def initialize(
    items,
    columns: [],
    read_denormalized_title: false,
    title_column: nil,
    read_denormalized_milestone: true,
    add_item_id_clause_to_column_values_query: false)

    @items = items
    @columns = columns
    @read_denormalized_title = read_denormalized_title
    @title_column = title_column
    @read_denormalized_milestone = read_denormalized_milestone
    @add_item_id_clause_to_column_values_query = add_item_id_clause_to_column_values_query
  end

  def build_partial_failure_response(error)
    {
      memex_project_column: error.memex_project_column,
      message: error.message.to_s
    }
  end

  # Prefills associations that are on or nested within a MemexProjectItem so
  # that we can serialize the given list of memex item efficiently.
  #
  # Returns MemexProjectItem::PrefilledAssociations if read_denormalized_title
  # is true, otherwise nil.
  # Can't set a #sig on this method to specify its return value because Sorbet will throw a RuntimeError:
  # "You're trying to replace `prefill` on `MemexProjectItemPrefiller`, but that method exists in a prepended module
  # (MemexProjectItemPrefiller::MemexProjectItemPrefillerTracingWrapper), which we don't currently support."
  def prefill
    if @read_denormalized_title && !@title_column
      raise ArgumentError, "must provide title_column alongside @read_denormalized_title"
    end

    # First fill in associations for generic and denormalized column values.
    fill_memex_project_column_values(@items)

    # Then build a map that will be used to initialize a
    # MemexProjectItem::PrefilledAssociations object at the end.
    draft_issue_ids_by_item_id = build_draft_issue_ids_by_item_id(@items, @read_denormalized_title)

    # Then collect all the pull requests and issues in separate arrays.
    issues = []
    issues_only = []  # issues that are not pull requests
    pull_requests = []
    draft_issues = []

    issue_ids = @items.map(&:issue_id).compact
    issues_only_ids = @items.filter(&:issue?).map(&:issue_id)

    if @read_denormalized_title
      # To reduce the number of queries required, we check for anything that might need issues, so that we can
      # re-use them more efficiently.
      if columns.find(&:issue_type?) || columns.find(&:parent_issue?)
        issues += Issue.where(id: issue_ids)
        issues_only += issues.filter { |i| issues_only_ids.include?(i.id) }
      end
    else
      # Prefill the top-level content associations.
      GitHub::PrefillAssociations.prefill_associations(@items, [:content])

      @items.each do |i|
        case i.content
        when Issue
          issues << i.content
          issues_only << i.content
        when PullRequest
          pull_requests << i.content
        when DraftIssue
          draft_issues << i.content
        end
      end

      # Load all the issues associated with a pull request.
      GitHub::PrefillAssociations.prefill_associations(pull_requests, [:issue])

      # Then collect all the issues from either plain issues or pull requests.
      issues += pull_requests.map(&:issue).compact
    end

    fill_options = if @read_denormalized_title
      {
        read_denormalized_title: true,
        issue_ids:,
        issues:,
        issues_only:,
        issues_only_ids:,
        issue_id_by_pull_request_id: @items.filter(&:pull_request?).map { |i| [i.content_id, i.issue_id] }.to_h,
        draft_issue_ids: draft_issue_ids_by_item_id.values,
        items: @items,
        draft_issue_ids_by_item_id: draft_issue_ids_by_item_id,
        read_denormalized_milestone: @read_denormalized_milestone
      }
    else
      {
        read_denormalized_title: false,
        issues: issues,
        issues_only: issues_only,
        draft_issues: draft_issues,
        pull_requests: pull_requests
      }
    end

    # Prefill labels.
    labels_by_issue_id = fill_memex_labels(@columns, fill_options)

    # Prefill linked pull requests.
    linked_pull_requests_by_issue_id = fill_memex_linked_pull_requests(@columns, fill_options)

    # Prefill tracked items progress
    item_completions_by_issue_id = fill_memex_items_completion(@columns, @items)

    # Prefill milestones.
    milestones_by_issue_id = fill_memex_milestones(@columns, fill_options)

    # Prefill issue types.
    issue_types_by_issue_id = fill_memex_issue_types(@columns, fill_options)

    # Prefill sub issue progress
    # Do this before prefilling parents, so we can reuse available records to prefill the parents' sub issue list
    # if the parents are in the project.
    sub_issues_progress_by_issue_id = fill_sub_issues_progress(@columns, fill_options)

    # Prefill parent issues.
    parent_issues_by_issue_id = fill_memex_parent_issues(@columns, fill_options)

    # Prefill tracked_by_items
    tracked_by_items_by_issue_id = {}
    partial_failures = []
    begin
      tracked_by_items_by_issue_id = fill_memex_tracked_by_items(@columns, @items)
    rescue MemexProjectItem::ItemPrefillError => err
      partial_failures.push(build_partial_failure_response(err))
    end

    # Prefill repositories on all issues, and also on all labels, milestones, parent issues, and
    # linked pull requests (because we eventually access the repository relation on
    # those objects too).
    labels = labels_by_issue_id.values.flatten.uniq
    milestones = milestones_by_issue_id.values.compact.uniq
    linked_prs = linked_pull_requests_by_issue_id.values.flatten.uniq
    parent_issues = parent_issues_by_issue_id.values.flatten.uniq

    repositories_by_issue_id = fill_memex_repositories(@columns, labels, milestones, linked_prs, parent_issues, fill_options)

    # Prefill assignees.
    assignees_by_issue_id = fill_memex_assignees(@columns, fill_options)
    assignees_by_draft_issue_id = fill_draft_issue_assignees(@columns, fill_options)

    # Prefill reviewers.
    reviewers_by_issue_id = fill_memex_reviewers(@columns, fill_options)

    # Prefill archivers for any archived items.
    archived_items = @items.select(&:archived?)
    if archived_items.present?
      GitHub::PrefillAssociations.prefill_associations(archived_items, [:archiver])
      fill_primary_avatars(archived_items.flat_map(&:archiver).compact.uniq(&:global_relay_id))
    end

    global_relay_ids = fill_global_relay_ids(@columns, fill_options)

    if @read_denormalized_title
      MemexProjectItem::PrefilledAssociations.new(
        title_column: @title_column,
        draft_issue_ids_by_item_id: draft_issue_ids_by_item_id,
        assignees_by_issue_id: assignees_by_issue_id,
        reviewers_by_issue_id: reviewers_by_issue_id,
        assignees_by_draft_issue_id: assignees_by_draft_issue_id,
        labels_by_issue_id: labels_by_issue_id,
        linked_pull_requests_by_issue_id: linked_pull_requests_by_issue_id,
        repositories_by_issue_id: repositories_by_issue_id,
        milestones_by_issue_id: @read_denormalized_milestone ? milestones_by_issue_id : milestones_by_issue_id.transform_values!(&:memex_column_hash),
        item_completions_by_issue_id: item_completions_by_issue_id,
        issue_types_by_issue_id: issue_types_by_issue_id,
        tracked_by_items_by_issue_id: tracked_by_items_by_issue_id,
        partial_failures: partial_failures,
        parent_issues_by_issue_id: parent_issues_by_issue_id,
        sub_issues_progress_by_issue_id: sub_issues_progress_by_issue_id,
        global_relay_ids_by_issue_id: global_relay_ids
      )
    else
      nil
    end
  end

  private

  # Prefills the `memex_project_column_values` association on each element of
  # the given array of items
  #
  # items - Array<MemexProjectItem> each item in a project to prefill
  #
  # Returns nil.
  def fill_memex_project_column_values(items)
    column_ids_to_load = @columns.select(&:generic_type?).map(&:id)
    column_ids_to_load << @title_column.id if @read_denormalized_title

    if @read_denormalized_milestone
      milestone_column = @columns.find(&:milestone?)
      if milestone_column
        column_ids_to_load << milestone_column.id
      end
    end

    memex_project_column_values_by_item_id = Hash.new { |h, k| h[k] = [] }
    if column_ids_to_load.any?
      scope = MemexProjectColumnValue.where(memex_project_column_id: column_ids_to_load.uniq)

      # Typically this clause that filters by item ID is omitted because we're fetching all items in a project
      # (i.e. up to MemexProjectItem::PER_PAGE_LIMIT), meaning that the clause would be too large and it is simpler
      # to filter just by (project-specific) column ID. If however this class is being called from a paginated context
      # (e.g. for the new Projects architecture backed by Elasticsearch), then we will be fetching at most 250 items,
      # and it is more efficient to add an additional filter by item ID than to retrieve column values for all items
      # in the project.
      scope = scope.where(memex_project_item_id: items.map(&:id)) if @add_item_id_clause_to_column_values_query

      scope.all.reduce(memex_project_column_values_by_item_id) do |memo, value_object|
        memo[value_object.memex_project_item_id] << value_object
        memo
      end
    end

    items.each do |item|
      item.association(:memex_project_column_values).target = memex_project_column_values_by_item_id[item.id]
    end

    memex_project_column_values_by_item_id
  end

  # For draft issues we can pull the draft_issue_id from the item directly since we already have it
  def build_draft_issue_ids_by_item_id(items, read_denormalized_title)
    return {} unless read_denormalized_title

    items.map do |item|
      [item.id, item.content_id] if item.draft_issue?
    end.compact.to_h
  end

  # Prefills the `labels` association on each of the given issues and returns
  # a map of label objects belonging to each issue.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the label column is not in this list, then this method won't
  #   make any database queries and will return an empty hash.
  # options - Hash containing one of two possible keys:
  #   :issues - Array<Issue> if the caller wants us to prefill associations
  #   :issue_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, Array<Label>>
  def fill_memex_labels(columns, options)
    return {} unless columns.find(&:labels?)
    validate_memex_fill_options!(options)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_associations(options[:issues], [:labels])
      all_labels = options[:issues].map(&:labels).flatten

      # Prefill HTML label names efficiently from memcache.
      Promise.all(all_labels.map(&:async_name_html)).sync

      options[:issues].reduce({}) do |memo, issue|
        memo[issue.id] = issue.sorted_labels
        memo
      end
    else
      labels_by_issue_id = IssuesLabels
        .select(:issue_id, :label_id)
        .includes(:label)
        .where(issue_id: options[:issue_ids])
        .group_by(&:issue_id)
        .transform_values { |i| Label.smart_sort(i.map(&:label).compact) }

      all_labels = labels_by_issue_id.values.flatten

      # Prefill HTML label names efficiently from memcache.
      Promise.all(all_labels.map(&:async_name_html)).sync

      labels_by_issue_id
    end
  end

  # Prefills the `issue_type` association on each of the given issues and returns
  # a map of IssueType objects belonging to each issue.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the label column is not in this list, then this method won't
  #   make any database queries and will return an empty hash.
  # options - Hash containing one of two possible keys:
  #   :issues_only - Array<Issue> if the caller wants us to prefill associations
  #   :issues_only_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, IssueType>
  def fill_memex_issue_types(columns, options)
    return {} unless columns.find(&:issue_type?)
    validate_memex_fill_options!(options)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_batch_method(options[:issues], :issue_type)

      options[:issues].reduce({}) do |memo, issue|
        # prefill_batch_method does not properly set the issue type assoication, and when checked it will not return as loaded
        issue.association(:issue_type).target = issue.issue_type

        memo[issue.id] = issue.issue_type
        memo
      end
    elsif options[:issues].present?
      GitHub::PrefillAssociations.prefill_batch_method(options[:issues], :issue_type)
      options[:issues].index_by(&:id).transform_values!(&:issue_type)
    else
      {}
    end
  end

  # Prefills the `parent_issue` column for all issues in a memex project, as well as the `sub_issue_list` association
  # on each of the parent issues. The sub_issue_list of the parent is used as metadata.
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the parent_issue column is not in this list, then this method won't
  #   make any database queries and will return an empty hash.
  # options - Hash containing one of two possible keys:
  #   :issues_only - Array<Issue> if the caller wants us to prefill associations
  #   :issues_only_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, Issue>, where the values in the hash are the parent issues
  def fill_memex_parent_issues(columns, options)
    return {} unless columns.find(&:parent_issue?)
    validate_memex_fill_options!(options)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_associations(options[:issues_only], [:parent_issue_relation])
      GitHub::PrefillAssociations.prefill_associations(
        options[:issues_only].flat_map(&:parent_issue_relation).compact,
        [{ source: :sub_issue_list }],
        available_records: options[:issues_only]
      )

      options[:issues_only].reduce({}) do |memo, issue|
        memo[issue.id] = issue.parent_issue_relation&.source
        memo
      end
    elsif options[:issues_only_ids].present?
      SubIssue
        .select(:source_issue_id, :target_issue_id)
        .includes(source: [:sub_issue_list])
        .where(target_issue_id: options[:issues_only_ids])
        .index_by(&:target_issue_id)
        .transform_values(&:source)
    else
      {}
    end
  end

  # Prefills the `sub_issue_list` association on each of the given issues and returns
  # a map of SubIssueList objects belonging to each issue.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller.
  # options - Hash containing one of two possible keys:
  #   :issues_only - Array<Issue> if the caller wants us to prefill associations
  #   :issues_only_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, SubIssueList>
  def fill_sub_issues_progress(columns, options)
    return unless columns.find(&:sub_issues_progress?)
    validate_memex_fill_options!(options)

    if options[:read_denormalized_title] && options[:issues_only_ids].present?
      SubIssueList.where(issue_id: options[:issues_only_ids]).index_by(&:issue_id)
    elsif !options[:read_denormalized_title] && options[:issues_only].present?
      GitHub::PrefillAssociations.prefill_associations(options[:issues_only], :sub_issue_list)
      options[:issues_only].index_by(&:id).transform_values!(&:sub_issue_list)
    else
      {}
    end
  end

  # Prefills global_relay_id which is used for both "potential" sub-issues in the memex item's content as well as
  # in the parent_issue column's value.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the parent_issue column is not in this list, then this method won't
  #   make any database queries and will return an empty hash.
  # options - Hash containing one of two possible keys:
  #   :issues - Array<Issue> if the caller wants us to prefill associations
  #   :issue_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, String>
  def fill_global_relay_ids(columns, options)
    return {} unless columns.find(&:parent_issue?)
    validate_memex_fill_options!(options)

    if options[:issues_only].present?
      GitHub::PrefillAssociations.prefill_associations(options[:issues_only], [:repository])
      options[:issues_only].index_by(&:id).transform_values!(&:global_relay_id)
    else
      {}
    end
  end

  # Prefills the `linked pull requests` association on each of the given issues
  # and returns a map of pull request objects belonging to each issue.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the linked_pull_requests column is not in this list, then this method won't
  #   make any database queries and will return an empty hash.
  # options - Hash containing one of two possible keys:
  #   :issues - Array<Issue> if the caller wants us to prefill associations
  #   :issue_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, Array<PullRequest>>
  def fill_memex_linked_pull_requests(columns, options)
    return {} unless columns.find(&:linked_pull_requests?)
    validate_memex_fill_options!(options)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_associations(options[:issues_only], [:close_issue_references])
      GitHub::PrefillAssociations.prefill_associations(options[:issues_only].flat_map(&:close_issue_references).compact, [:pull_request])
      GitHub::PrefillAssociations.prefill_associations(options[:issues_only].flat_map(&:close_issue_references).compact.map(&:pull_request).compact, [:issue])
      options[:issues_only].reduce({}) do |memo, issue|
        memo[issue.id] = issue.close_issue_references
        .map(&:pull_request)
        memo
      end
    else
      CloseIssueReference
        .select(:issue_id, :pull_request_id)
        .includes(pull_request: :issue)
        .where(issue_id: options[:issues_only_ids])
        .group_by(&:issue_id)
        .transform_values { |i| i.map(&:pull_request).compact.sort_by(&:number) }
    end
  end

  def fill_memex_items_completion(columns, items)
    return {} unless columns.find(&:tracks?)
    return {} if items.empty?

    result = {}
    GitHub::PrefillAssociations
      .prefill_batch_method(items, :completion)
      .map { |item| result[item.content_id] = item.completion }
    result
  end

  def fill_memex_tracked_by_items(columns, items)
    return {} unless columns.find(&:tracked_by?)
    return {} if items.empty?

    excluding_drafts = items.reject(&:draft_issue?)
    return {} if excluding_drafts.empty?

    result = {}
    GitHub::PrefillAssociations
      .prefill_batch_method(excluding_drafts, :tracked_by_items)
      .map { |item| result[item.content_id] = item.tracked_by_items }
    result
  end

  # Prefills the `milestone` association on each of the given issues and
  # returns a map of milestone objects belonging to each issue.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the milestone column is not in this list, then this method
  #   won't make any database queries and will return an empty hash.
  # options - Hash containing one of two possible keys:
  #   :issues - Array<Issue> if the caller wants us to prefill associations
  #   :issue_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, Milestone?>
  def fill_memex_milestones(columns, options)
    milestone_column = columns.find(&:milestone?)
    return {} unless milestone_column

    validate_memex_fill_options!(options)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_associations(options[:issues], [:milestone])

      options[:issues].reduce({}) do |memo, issue|
        memo[issue.id] = issue.milestone
        memo
      end
    elsif options[:read_denormalized_milestone]
      options[:items].reduce({}) do |memo, item|
        next memo unless item.issue_id

        milestone_column_value = item.memex_project_column_values.find { |v| v.memex_project_column_id == milestone_column.id }
        next memo unless milestone_column_value

        result = milestone_column_value.json_value&.fetch("value", nil)
        result.symbolize_keys! if result.is_a?(Hash)

        memo[item.issue_id] = result
        memo
      end
    else
      Issue
        .select(:id, :milestone_id)
        .includes(:milestone)
        .where(id: options[:issue_ids])
        .where.not(milestone_id: nil)
        .index_by(&:id)
        .transform_values!(&:milestone)
    end
  end

  # Prefills the `repository` association on each of the given objects and
  # returns a map of repository objects belonging to just the given issues.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the repository column is not in this list, then this method
  #   will return an empty hash.
  # labels_and_milestones - Array<Label | Milestone>
  # options - Hash containing one of two possible keys:
  #   :issues - Array<Issue> if the caller wants us to prefill associations
  #   :items - Array<MemexProjectItem> if the caller wants us to return a Hash that can
  #     be used to populate `MemexProjectItem::PrefilledAssociations`.
  #
  # Returns Hash<Integer, Repository> or nil.
  def fill_memex_repositories(columns, labels, milestones, linked_prs, parent_issues, options)
    validate_memex_fill_options!(options)

    repo_objects = labels + linked_prs + parent_issues
    repo_objects += milestones unless options[:read_denormalized_milestone]

    # options[:issues] is set when read_denormalized_title is false or issue_type or parent_issue columns are visible.
    # additional_repo_objects is used here to ensure that when we attempt to read the repository below, we are reading
    # from the same set of "objects" that had their associations prefilled.
    additional_repo_objects = options[:issues].empty? ? options[:items] : options[:issues]

    if additional_repo_objects.present?
      repo_objects += additional_repo_objects
    end

    GitHub::PrefillAssociations.prefill_associations(repo_objects, :repository)

    return {} unless columns.find(&:repository?) || columns.find(&:title?)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_associations(options[:issues].map(&:repository), [:owner, :organization])

      nil
    else
      additional_repo_objects.reduce({}) do |memo, i|
        id = i.is_a?(Issue) ? i.id : i.issue_id
        next memo unless i.repository
        next memo unless id

        memo[id] = i.repository
        memo
      end
    end
  end

  # Prefills the `assignees` association on each of the given issues and
  # returns a map of assignee (i.e. user) objects belonging to each issue.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the assignee column is not in this list, then this method
  #   won't make any database queries and will return an empty hash.
  # options - Hash containing one of two possible keys:
  #   :issues - Array<Issue> if the caller wants us to prefill associations
  #   :issue_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, Array<User>> or nil.
  def fill_memex_assignees(columns, options)
    return {} unless columns.find(&:assignees?)

    validate_memex_fill_options!(options)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_associations(options[:issues], [:assignees])
      fill_primary_avatars(options[:issues].map(&:assignees).flatten)

      # Providing options[:issues] implies that we're not reading from
      # denormalized data, in which case there is no need to return anything.
      nil
    else
      users_by_issue_id = Assignment
        .select(:issue_id, :assignee_id)
        .includes(:assignee)
        .where(issue_id: options[:issue_ids])
        .group_by(&:issue_id)
        .transform_values! { |a| a.map(&:assignee).compact.sort_by { |a| a.display_login.downcase } }

      fill_primary_avatars(users_by_issue_id.values.flatten)

      users_by_issue_id
    end
  end

  # Prefills the `reviewers` association on each of the given issues and
  # returns a map of reviewer and review status objects belonging to each issue.
  #
  # columns - Array<MemexProjectColumn> for all columns requested by the
  #   caller. If the reviewers column is not in this list, then this method
  #   won't make any database queries and will return an empty hash.
  # options - Hash containing one of two possible keys:
  #   :issues - Array<Issue> if the caller wants us to prefill associations
  #   :issue_ids - Array<Integer> if the caller wants us to return a Hash that
  #     can be used to populate `MemexProjectItem::PrefilledAssociations`
  #
  # Returns Hash<Integer, Array<Reviewers>> or nil.
  def fill_memex_reviewers(columns, options)
    return {} unless columns.find(&:reviewers?)

    validate_memex_fill_options!(options)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_associations(options[:pull_requests], [:review_requests, :reviews, :user])
      GitHub::PrefillAssociations.prefill_associations(options[:pull_requests].flat_map(&:review_requests).compact, [:reviewer, :pull_request_reviews])
      GitHub::PrefillAssociations.prefill_associations(options[:pull_requests].flat_map(&:reviews).compact, [:user])

      fill_primary_avatars(
        (
          options[:pull_requests].flat_map(&:review_requests).flat_map(&:reviewer) +
          options[:pull_requests].flat_map(&:reviews).flat_map(&:user)
        ).compact.uniq(&:global_relay_id)
      )

      nil
    else
      reviews = []
      requested = []
      pull_request_ids = options[:issue_id_by_pull_request_id].keys

      pull_request_ids.each_slice(IN_CLAUSE_BATCH_SIZE) do |pull_request_ids_in_batch|
        reviews.concat PullRequestReview
          .includes(:user, :pull_request)
          .submitted
          .where(pull_request_id: pull_request_ids_in_batch)
          .to_a # ensure the query is executed

        requested.concat ReviewRequest
          .includes(:reviewer, :pull_request_reviews)
          .where(pull_request_id: pull_request_ids_in_batch)
          .to_a # ensure the query is executed
          # Current index limitations mean that it may be easier to do this in Ruby than the SQL query:
          .select { |r| r.pending? && !r.deferred? && !r.dismissed? }
          # Exclude any review requests from reviewers that may no longer exist (example: deleted team)
          .select { |r| r.reviewer.present? }
      end

      fill_primary_avatars(
        (reviews.map(&:user) + requested.map(&:reviewer)).compact.uniq(&:global_relay_id)
      )

      transformed_reviews =
        reviews
        .group_by(&:pull_request_id)
        .transform_values! do |reviews_for_pr|
          reviews_for_pr
            .reject do |r|
              T.must(r.pull_request).user_id == r.safe_user.id || # don't include reviews by the PR author
              r.safe_user.ghost? # don't include ghost reviewers (i.e., deleted user accounts)
            end
            .uniq(&:user_id)
            .sort_by { |r| T.must(r.id) }
            .reverse
            .map { |review| pull_request_review_hash(review) }
        end

      transformed_requested =
        requested
        .group_by(&:pull_request_id)
        .transform_values! do |review_requests_for_pr|
          review_requests_for_pr
            .sort_by { |r| T.must(r.id) }
            .reverse
            .map { |review_request| review_request_hash(review_request) }
        end

      reviewers_by_pull_request_id = options[:issue_id_by_pull_request_id].keys.each_with_object({}) do |pull_request_id, hsh|
        # This is a way to try to get a Set of users/teams without having access
        # to the underlying object. We built strings based on the type and id as
        # essentially a hashed user identifier. We prefer pull pending review
        # requests over reviews, so we'll so we'll exclude any submited reviewer
        # from the list if they are already in the list of requested reviewers.
        # This covers the use case of re-requesting a review..
        #
        # We can't make the list uniq before this point because we need the list
        # to be unique intersection of requested review and submitted review per
        # Pull Request
        #
        # Put another way, this is:
        # - get all the review_requests unique by reviewer
        # - get all the reviews unique by reviewer
        # - remove submitted reviews where there is a pending request for the same reviewer
        # - combine the two lists and compact
        pending_requests =
          Array.wrap(transformed_requested[pull_request_id])
          .uniq { |r| hashed_reviewer(r[:reviewer]) }

        hashed_submitted_requested_users =
          pending_requests
          .map { |r| hashed_reviewer(r[:reviewer]) }

        submitted_reviews_less_pending_requested_reviews =
          Array.wrap(transformed_reviews[pull_request_id])
          .reject { |r| hashed_submitted_requested_users.include?(hashed_reviewer(r[:reviewer])) }
          .uniq { |r| r.dig(:reviewer, :id) }

        hsh[pull_request_id] = (
          submitted_reviews_less_pending_requested_reviews +
          pending_requests
        ).compact
      end

      options[:issue_id_by_pull_request_id].reduce({}) do |memo, (pull_request_id, issue_id)|
        memo[issue_id] = reviewers_by_pull_request_id[pull_request_id]
        memo
      end
    end
  end

  def fill_draft_issue_assignees(columns, options)
    return {} unless columns.find(&:assignees?)

    if !options[:read_denormalized_title]
      GitHub::PrefillAssociations.prefill_associations(options[:draft_issues], [:assignees])
      fill_primary_avatars(options[:draft_issues].map(&:assignees).flatten)
      nil
    else
      users_by_draft_issue_id = DraftIssueAssignment
        .select(:target_id, :assignee_id)
        .includes(:assignee)
        .where(target_type: DraftIssue.name, target_id: options[:draft_issue_ids])
        .group_by(&:target_id)
        .transform_values! { |a| a.map(&:assignee).compact.sort_by { |a| a.display_login.downcase } }

      fill_primary_avatars(users_by_draft_issue_id.values.flatten)

      users_by_draft_issue_id
    end
  end

  # Prefills the `primary_avatar` association on each of the given users.
  #
  # users - Array<User>
  #
  # Returns nil.
  def fill_primary_avatars(users)
    primary_avatars_by_user_id = PrimaryAvatar
      .where(owner_id: users.map(&:id).uniq, owner_type: "User")
      .index_by(&:owner_id)

    users.each { |u| u.primary_avatar = primary_avatars_by_user_id[u.id] }

    nil
  end

  def validate_memex_fill_options!(options)
    unless options.has_key?(:read_denormalized_title)
      raise ArgumentError, "must provide :read_denormalized_title"
    end

    if options[:read_denormalized_title] && options[:issue_ids].nil? && options[:items].nil?
      raise ArgumentError, "must provide either :issue_ids or :items when reading denormalized titles"
    end

    if !options[:read_denormalized_title] && options[:issues].nil?
      raise ArgumentError, "must provide :issues if not reading denormalized titles"
    end
  end

  # This is a temporary function to fetch the memex project that owns the items,
  # which is used for checking feature flag membership.
  sig { returns(T.nilable(T.any(User, Organization))) }
  def memex_owner
    @items.first&.memex_project&.owner
  end
end
