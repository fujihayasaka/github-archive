# typed: true
# frozen_string_literal: true

class MemexProjectItemRedactor
  include GitHub::Tracing
  include GitHub::Memoizer

  trace_method(
    :items,
    span_annotator: ->(redactor, span, _context, result) do
      input_height = redactor.unredacted_items.length
      output_height = result.count do |item|
        item.content_type != MemexProjectItem::REDACTED_ITEM_TYPE
      end

      span.add_attributes({
        "gh.memex.redactor.input_height" => input_height,
        "gh.memex.redactor.input_height_bucket" => MemexPerformanceStatsHelper.height_bucket(input_height),
        "gh.memex.redactor.output_height" => output_height,
        "gh.memex.redactor.output_height_bucket" => MemexPerformanceStatsHelper.height_bucket(output_height),
        "gh.memex.redactor.has_prefilled_associations" => redactor.prefilled_associations.present?,
        "gh.memex.redactor.has_cap_filter" => redactor.cap_filter.present?,
      })
    end
  )

  trace_method(
    :redacted_issue_ids,
    span_annotator: ->(redactor, span, _context, result) do
      span.add_attributes({
        "gh.memex.redactor.has_linked_pull_requests_field" => redactor.columns.any?(&:linked_pull_requests?),
        "gh.memex.redactor.output_height" => result.length,
        "gh.memex.redactor.output_height_bucket" => MemexPerformanceStatsHelper.height_bucket(result.length),
      })
    end
  )

  attr_reader :unredacted_items, :columns, :prefilled_associations, :cap_filter

  # Initialize a MemexProjectItemRedactor with the given parameters.
  # viewer: The viewer for which to determine authorization.
  # items: The MemexProjectItems to be checked for redaction.
  # columns: The MemexProjectColumns to be checked for redaction, if applicable.  Ex: Linked Pull Requests.
  # prefilled_associations: The hash of prefilled associations from denormalized data, if applicable.
  # cap_filter: The Conditional Access Policy filter to use, if applicable.
  def initialize(viewer:, items:, columns: nil, prefilled_associations: nil, cap_filter: nil)
    @viewer = viewer
    @unredacted_items = items
    @columns = Array.wrap(columns)
    @prefilled_associations = prefilled_associations
    @cap_filter = cap_filter
  end

  # Returns an array of MemexProjectItems that have been processed for redaction.
  def items
    @items_with_redactions ||= begin
      cap_filtered_items = cap_unauthorized_resources(visible_items)

      GitHub.dogstats.increment("memex.cap_filtering", tags: [
        "memex_cap_filtering_enabled:#{@cap_filter.present?}",
        "has_cap_filtered_items:#{cap_filtered_items.any?}"
      ])

      redact_items(cap_filtered_items)
    end
  end

  memoize def visible_items
    @unredacted_items.reject do |item|
      item.hide_from_user?(@viewer)
    end
  end

  def redact_items(cap_filtered_items)
    visible_items.map do |item|
      next item.redact! if cap_filtered_items.include?(item)
      authorized_item?(item) ? item : item.redact!
    end
  end

  # Returns an array of issue IDs from specific column data that should be removed from serialization to the client.
  # These issues should not be visible to the viewer because they failed authorization or Conditional Access Policy (CAP) checks.
  # Note: to support denormalized values, Spammy linked PRs are not redacted.
  def redacted_issue_ids
    @redacted_issue_ids ||= begin
      unauthorized_objects, authorized_objects = column_authorizables.partition do |authable|
        visible_issue_ids.exclude?(authable.issue_id)
      end
      unauthorized_objects.push(*cap_unauthorized_objects(authorized_objects)).map(&:issue_id)
    end + redacted_tracked_by_items(@unredacted_items)
    @redacted_issue_ids.compact.uniq
  end

  private

  # Returns an array of Issue::Authorizables from specific column data that should be checked for redaction.
  # For example, linked pull requests could live in different repos and orgs than the item itself.
  def column_authorizables
    return @column_authorizables if defined?(@column_authorizables)

    @column_authorizables = []

    if @columns&.find(&:linked_pull_requests?)
      @column_authorizables += @unredacted_items.flat_map { |item| linked_pull_request_authorizables(item) }.compact.uniq
    end

    if @columns&.find(&:parent_issue?)
      @column_authorizables += @unredacted_items.map { |item| parent_issue_authorizable(item) }.compact.uniq
    end

    @column_authorizables
  end

  # Returns an array of Issue::Authorizables from linked pull requests associated with the given item.
  def linked_pull_request_authorizables(item)
    return [] unless item.issue?
    if @prefilled_associations.present?
      linked_prs = @prefilled_associations.linked_pull_requests(item)
      return [] unless linked_prs.any?
      # Check if we have ActiveRecord PullRequests vs a denormalized pull request hash (memex_read_denormalized_linked_prs FF)
      if linked_prs[0].respond_to?(:head_sha)
        linked_prs.map(&:to_issue_authorizable)
      else
        linked_prs.map { |pr| Issue::Authorizable.new(pr.issue_id, pr.repository_id) }
      end
    else
      # If we're here, then all Memex denormalization is disabled.
      item.content.close_issue_references.map(&:pull_request).map(&:to_issue_authorizable)
    end
  end

  # Returns an array of Issue::Authorizables from the parent issue of a given item
  def parent_issue_authorizable(item)
    return unless item.issue?
    if @prefilled_associations.present?
      @prefilled_associations.parent_issue(item)&.to_issue_authorizable
    else
      # If we're here, then all Memex denormalization is disabled.
      relation = item.content.parent_issue_relation
      return unless relation
      relation.source_issue_authorizable
    end
  end

  def redacted_tracked_by_items(items)
    return [] unless @prefilled_associations.present?
    tracked_by_items = items.flat_map { |item| @prefilled_associations.tracked_by_items(item) }.compact
    return [] unless tracked_by_items.any?

    # We are using T.cast here because while the `exclude_redacted_issues: true` option should
    # ensure that no redacted issues are returned, there isn't a way to express that conditional
    # type in the Sorbet type system currently.
    redacted_issues = T.cast(TasklistBlocks::Redactor.new(
      viewer: @viewer,
      issues: tracked_by_items,
      cap_filter: @cap_filter,
      options: { exclude_redacted_issues: true }
    ).issues, T::Array[TasklistBlocks::Issue])

    tracked_by_items.map(&:issue_id) - redacted_issues.map(&:issue_id)
  end

  # Returns an array of Issue::Authorizables that fail Conditional Access Policy checks based on the repository owners.
  def cap_unauthorized_objects(authorizables)
    authorizables_by_repo_id = authorizables.group_by(&:repository_id)
    repos_by_owner_id = Repository
      .where(id: authorizables_by_repo_id.keys)
      .pluck(:id, :owner_id)
      .reduce(Hash.new { |h, k| h[k] = [] }) do |hash, repo_owner|
        hash[repo_owner[1]] << repo_owner[0]
        hash
      end
    owners = User.where(id: repos_by_owner_id.keys)

    cap_unauthorized_owners = cap_unauthorized_resources(owners)
    cap_unauthorized_repo_ids = cap_unauthorized_owners.flat_map { |owner| repos_by_owner_id[owner.id] }
    cap_unauthorized_repo_ids.flat_map { |repo_id| authorizables_by_repo_id[repo_id] }
  end

  # Conditional Access Policy filtering
  # Returns an array of resources that were "unsatisfied" for any of the conditional access policies
  def cap_unauthorized_resources(resources)
    return [] unless @cap_filter.present?
    Set.new(@cap_filter.unauthorized_resources(resources))
  end

  # Determine if the MemexProjectItem has passed authorization checks performed
  # for the current viewer.
  def authorized_item?(item)
    case item.content_type
    when "Issue"
      visible_issue_ids.include?(item.issue_id)
    when "PullRequest"
      visible_issue_ids.include?(item.issue_id)
    when "DraftIssue"
      true
    else
      false
    end
  end

  # Returns an array of visible issue IDs for the current viewer based on authorized access to the issue repositories.
  # This checks row items as well as relevant column data.
  def visible_issue_ids
    return @visible_issue_ids if defined?(@visible_issue_ids)

    @visible_issue_ids = Issue.visible_ids_for(
      viewer: @viewer,
      authorizables: @unredacted_items.map(&:to_issue_authorizable) + column_authorizables
    )
  end

  trace_method :visible_items
  trace_method :redact_items
  trace_method :visible_issue_ids
end
