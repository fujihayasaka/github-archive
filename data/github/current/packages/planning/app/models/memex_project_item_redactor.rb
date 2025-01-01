# typed: true
# frozen_string_literal: true

class MemexProjectItemRedactor
  include GitHub::Tracing
  include GitHub::Memoizer

  # Metrics for the items and redacted_issue_ids methods used with query_redactor_results passed in from the Memex Without Limits (MWL) Elasticsearch query.
  UNEXPECTED_ITEMS_CHECK_LOG_MESSAGE = "A project item was checked by the legacy item redactor rather than the Elasticsearch query redactor"
  UNEXPECTED_ITEMS_CHECK_SUMMARY_LOG_MESSAGE = "Project items were checked by the legacy item redactor rather than the Elasticsearch query redactor"
  UNEXPECTED_ITEMS_CHECK_METRIC = "memex_project_item_redactor.items.unexpected_legacy_checks"
  ZERO_ITEMS_CHECK_METRIC = "memex_project_item_redactor.items.zero_legacy_checks"
  ZERO_ISSUES_CHECK_METRIC = "memex_project_item_redactor.redacted_issue_ids.zero_legacy_checks"
  NON_ZERO_ISSUES_CHECK_METRIC = "memex_project_item_redactor.redacted_issue_ids.non_zero_legacy_checks"

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
  # query_redactor_results: Optional MWL MemexProjectItemQueryRedactor redaction results that can be used
  #   to avoid redundant repository authorization (including Conditional Access Policies (CAP)) and spammy checks.
  sig do
    params(
      viewer: T.nilable(User),
      items: T.any(T::Array[MemexProjectItem], ActiveRecord::AssociationRelation),
      columns: T.nilable(T.any(MemexProjectColumn, T::Array[MemexProjectColumn], ActiveRecord::AssociationRelation, ActiveRecord::Associations::CollectionProxy)),
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
      cap_filter: T.nilable(ConditionalAccess::Filter),
      query_redactor_results: T.nilable(Search::Queries::MemexProjectItemQueryRedactor::Results)
    ).void
  end
  def initialize(viewer:, items:, columns: nil, prefilled_associations: nil, cap_filter: nil, query_redactor_results: nil)
    @viewer = viewer
    @unredacted_items = T.let(items.to_a, T::Array[MemexProjectItem])
    @columns = T.let(Array.wrap(columns), T.nilable(T::Array[MemexProjectColumn]))
    @prefilled_associations = prefilled_associations
    @cap_filter = cap_filter
    @query_redactor_results = query_redactor_results

    # create sets for faster lookup
    @authorized_repo_ids_set = (@query_redactor_results&.authorized_repo_ids || []).to_set
    @unauthorized_repo_ids_set = (@query_redactor_results&.unauthorized_repo_ids || []).to_set

    @column_authorizables = T.let(nil, T.nilable(T::Array[Issue::Authorizable]))
  end

  # Returns an array of MemexProjectItems that have been processed for redaction.
  def items
    return @items_with_redactions unless @items_with_redactions.nil?

    # If we have query_redactor_results passed in from the MWL Elasticsearch query, then we expect to have only authorized items.
    # Any non-authorized items would indicate a problem, so fall back to legacy redaction if so.
    if use_preauthorizations?
      authorized_items, non_authorized_items = visible_items.partition { |item| item.draft_issue? || is_preauthorized?(item.repository_id) }
      log_legacy_redactor_items_check(authorized_items:, non_authorized_items:)

      @items_with_redactions = authorized_items unless non_authorized_items.length > 0
    end

    if @items_with_redactions.nil?
      cap_filtered_items = cap_unauthorized_resources(visible_items)

      GitHub.dogstats.increment("memex.cap_filtering", tags: [
        "memex_cap_filtering_enabled:#{@cap_filter.present?}",
        "has_cap_filtered_items:#{cap_filtered_items.any?}"
      ])

      @items_with_redactions = redact_items(cap_filtered_items)
    end
    @items_with_redactions
  end

  # Returns an array of issue IDs from specific column data that should be removed from serialization to the client.
  # These issues should not be visible to the viewer because they failed authorization or Conditional Access Policy (CAP) checks.
  # Note: to support denormalized values, Spammy linked PRs are not redacted.
  def redacted_issue_ids
    return @redacted_issue_ids unless @redacted_issue_ids.nil?

    unknown_authorizables = column_authorizables
    unauthorized_issue_ids = []

    # If we have query_redactor_results passed in from the Memex Without Limits (MWL) Elasticsearch query,
    # then first check issues against the known authorized/unauthorized repo_ids,
    # and augment with the legacy redaction checks only if needed.
    if use_preauthorizations?
      return [] unless column_authorizables.present?

      pre_authorized_objects, non_authorized_objects = column_authorizables.partition { |authable| is_preauthorized?(authable.repository_id) }
      pre_unauthorized_objects, unknown_authorizables = non_authorized_objects.partition { |authable| is_pre_unauthorized?(authable.repository_id) }
      unauthorized_issue_ids = pre_unauthorized_objects.map(&:issue_id).compact.uniq

      requires_legacy_checks = unknown_authorizables.map(&:issue_id).compact.length > 0
      log_legacy_redactor_issues_check(requires_legacy_checks)

      @redacted_issue_ids = unauthorized_issue_ids
    end

    if @redacted_issue_ids.nil? || requires_legacy_checks
      unauthorized_objects, authorized_objects = unknown_authorizables.partition do |authable|
        visible_issue_ids.exclude?(authable.issue_id)
      end
      unauthorized_issue_ids += unauthorized_objects.push(*cap_unauthorized_objects(authorized_objects)).map(&:issue_id)
      # Tracked-by is not supported in MWL, so no need to check for those values in the MWL query_redactor_results case above.
      unauthorized_issue_ids += redacted_tracked_by_items(@unredacted_items)
      unauthorized_issue_ids.compact.uniq
    end
    @redacted_issue_ids = unauthorized_issue_ids
  end

  # Returns an array of MemexProjectItems that are visible to the viewer based on spammy checks.
  # These might still be "spammy" since spammy users and site admins can see spammy items.
  sig { returns(T::Array[MemexProjectItem]) }
  memoize private def visible_items
    return Array.new(@unredacted_items) if @query_redactor_results&.checked_for_spam

    @unredacted_items.reject do |item|
      # T.unsafe: The viewer can be nil (anonymous) and the Spammable module checks for that, but the method type isn't nilable.
      item.hide_from_user?(T.unsafe(@viewer))
    end
  end

  private def redact_items(cap_filtered_items)
    visible_items.map do |item|
      next item.redact! if cap_filtered_items.include?(item)
      authorized_item?(item) ? item : item.redact!
    end
  end

  # Returns an array of Issue::Authorizables from specific column data that should be checked for redaction.
  # For example, linked pull requests could live in different repos and orgs than the item itself.
  sig { returns(T::Array[Issue::Authorizable]) }
  private def column_authorizables
    return @column_authorizables unless @column_authorizables.nil?

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
  sig { params(item: MemexProjectItem).returns(T::Array[Issue::Authorizable]) }
  private def linked_pull_request_authorizables(item)
    return [] unless item.issue?

    if @prefilled_associations.present?
      return [] unless (linked_prs = @prefilled_associations.linked_pull_requests(item))
      # Check if we have ActiveRecord PullRequests vs a denormalized pull request hash (memex_read_denormalized_linked_prs FF)
      if linked_prs[0].respond_to?(:head_sha)
        linked_prs.map(&:to_issue_authorizable)
      else
        linked_prs.map { |pr| Issue::Authorizable.new(T.must(pr.issue).id, pr.repository_id) }
      end
    else
      # If we're here, then all Memex denormalization is disabled.
      issue = T.cast(item.content, Issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      issue.close_issue_references.map(&:pull_request).compact.map(&:to_issue_authorizable)
    end
  end

  # Returns an array of Issue::Authorizables from the parent issue of a given item
  sig { params(item: MemexProjectItem).returns(T.nilable(Issue::Authorizable)) }
  private def parent_issue_authorizable(item)
    return unless item.issue?

    if @prefilled_associations.present?
      @prefilled_associations.parent_issue(item)&.to_issue_authorizable
    else
      # If we're here, then all Memex denormalization is disabled.
      issue = T.cast(item.content, Issue)
      relation = issue.parent_issue_relation
      return unless relation
      relation.source_issue_authorizable
    end
  end

  private def redacted_tracked_by_items(items)
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
  private def cap_unauthorized_objects(authorizables)
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
  private def cap_unauthorized_resources(resources)
    return [] unless @cap_filter.present?
    Set.new(@cap_filter.unauthorized_resources(resources))
  end

  # Determine if the MemexProjectItem has passed authorization checks performed
  # for the current viewer.
  private def authorized_item?(item)
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
  private def visible_issue_ids
    return @visible_issue_ids if defined?(@visible_issue_ids)

    @visible_issue_ids = Issue.visible_ids_for(
      viewer: @viewer,
      authorizables: @unredacted_items.map(&:to_issue_authorizable) + column_authorizables
    )
  end

  # Returns true if we can use preauthorized repository results to avoid redundant legacy redactions.
  private def use_preauthorizations?
    @query_redactor_results.present?
  end

  # Returns true if the repository was already authorized for viewing by the current user, including CAP.
  private def is_preauthorized?(repository_id)
    @authorized_repo_ids_set.include?(repository_id)
  end

  # Returns true if the repository was already checked but found to be not authorized for viewing by the current user.
  private def is_pre_unauthorized?(repository_id)
    @unauthorized_repo_ids_set.include?(repository_id)
  end

  # When providing query_redactor_results with authorized_repo_ids, we do not expect to see
  # any non_authorized items (explicitly unauthorized or not checked).
  sig { params(authorized_items: T::Array[MemexProjectItem], non_authorized_items: T::Array[MemexProjectItem]).void }
  private def log_legacy_redactor_items_check(authorized_items:, non_authorized_items:)

    if non_authorized_items.any?

      GitHub.logger.info(
        UNEXPECTED_ITEMS_CHECK_SUMMARY_LOG_MESSAGE,
        {
          "code.namespace" => self.class.name,
          "code.function" => "result",
          "gh.memex.project.id" => non_authorized_items.first&.memex_project_id,
          "gh.memex.items.auth.count" => authorized_items.count,
          "gh.memex.items.draft.count" => authorized_items.count(&:draft_issue?),
          "gh.memex.items.unauth.count" => non_authorized_items.count,
          "gh.memex.repo.auth.ids" => @query_redactor_results&.authorized_repo_ids,
          "gh.memex.repo.unauth.ids" => @query_redactor_results&.unauthorized_repo_ids,
          "gh.user.id" => @viewer&.id
        }
      )

      non_authorized_items.each do |item|
        GitHub.logger.info(
          UNEXPECTED_ITEMS_CHECK_LOG_MESSAGE,
          {
            "code.namespace" => self.class.name,
            "code.function" => "result",
            "gh.memex.project.id" => item.memex_project_id,
            "gh.memex.item.id" => item.id,
            "gh.memex.item.content.type" => item.content_type,
            "gh.memex.item.repo.id" => item.repository_id,
            "gh.user.id" => @viewer&.id
          }
        )
      end
    end

    if non_authorized_items.any?
      GitHub.dogstats.count(UNEXPECTED_ITEMS_CHECK_METRIC, non_authorized_items.count)
    else
      GitHub.dogstats.increment(ZERO_ITEMS_CHECK_METRIC)
    end

    nil
  end

  # Log stats if we had to resort to the legacy redaction code to authorize
  # any column values that feel outside the authorized_repo_ids provide in query_redactor_results
  sig { params(requires_legacy_checks: T::Boolean).void }
  private def log_legacy_redactor_issues_check(requires_legacy_checks)
    if requires_legacy_checks
      GitHub.dogstats.increment(NON_ZERO_ISSUES_CHECK_METRIC)
    else
      GitHub.dogstats.increment(ZERO_ISSUES_CHECK_METRIC)
    end

    nil
  end
end
