# typed: true
# frozen_string_literal: true

# methods to be mixed into the Issue model
module Issue::IssuesGraphDependency
  extend ActiveSupport::Concern
  include HierarchyHelper

  extend T::Helpers

  requires_ancestor { Issue }

  STAT_PREFIX = "issues_graph"
  CACHE_STATS_KEY = "issues_graph.sync_hierarchy_state.cache"
  ISSUE_ITEM_TYPE = "ISSUE"

  # TODO: adjust this value down once we have a better idea of denormalized lag time.
  # This seems like it can be pretty high in codespace development, but in production should
  # be much lower.
  LAST_MODIFIED_AT_MIN_AGE_FOR_DENORMALIZED_GET = 10.seconds
  ISSUES_GRAPH_CACHE_TTL = 5.seconds
  NOTIFY_TRACKING_ISSUES_WAIT_TIME = 4.seconds

  def hierarchy_state
    return @hierarchy_state if @hierarchy_state
    # Checking if issue is persisted before feature flag as its a cheaper condition to perform.
    if new_record?
      increment("issues.hierarchy.state.sync", tags: ["result:skipped", "reason:new_record"])
      @hierarchy_state = nil
      return
    end

    unless tasklist_blocks_enabled?
      increment("issues.hierarchy.state.sync", tags: ["result:skipped", "reason:feature_flag"])
      @hierarchy_state = nil
      return
    end

    result = if repository&.feature_enabled?(:issues_graph_api_concurrent_faraday)
      async_hierarchy_state&.sync
    else
      sync_hierarchy_state
    end

    # in case it's not persisted, result will be nil
    return nil if result.nil?

    if result.success?
      increment("issues.hierarchy.state.sync", tags: ["result:success"])
    else
      increment("issues.hierarchy.state.sync", tags: ["result:error", "code:#{result.error_code}"])
    end

    @hierarchy_state = result.data
  end

  def preload_hierarchy_state(viewer: nil)
    if repository&.feature_enabled?(:issues_graph_api_concurrent_faraday)
      async_hierarchy_state(viewer: viewer)
    else
      sync_hierarchy_state(viewer: viewer)
    end
  end

  def sync_hierarchy_state(viewer: nil)
    return unless persisted? && tasklist_blocks_enabled?
    return unless GitHub.flipper[:issue_hierarchy_state].enabled?

    cache_enabled = GitHub.flipper[:hierarchy_cache_key].enabled?
    GitHub.dogstats.distribution_time("issues.tracking_blocks.cached_get_issue.time", tags: ["cache_enabled:#{cache_enabled}"]) do
      if user && cache_enabled && tasklist_block_markdown_at_rest_enabled?
        response = GitHub.cache.fetch(get_issue_cache_key, ttl: ISSUES_GRAPH_CACHE_TTL, stats_key: CACHE_STATS_KEY) do
          client_response = GitHub.issues_graph_api_client_strict.get_issue(
            **common_get_issue_options(viewer),
            stat_tags: ["context:sync_hierarchy_state"]
          )

          # Convert response object to json string for cachign
          jsonify_hierarchy_state(client_response)
        end

        response_hash = JSON.parse(response)
        unless response_hash["status"] == "success"
          get_issue_error = Twirp::Error.new(response_hash["error_code"], response_hash["error_message"])
          return ::IssuesGraph::Result.error(get_issue_error)
        end

        # Rehydrate cached content into expected response object
        get_issue_response = IssuesGraph::Proto::GetIssueResponse.new(**response_hash["data"])
        ::IssuesGraph::Result.success(get_issue_response)
      else
        GitHub.issues_graph_api_client_strict.get_issue(
          **common_get_issue_options(viewer),
          stat_tags: ["context:sync_hierarchy_state"]
        )
      end
    end
  end

  def get_issue_cache_key
    [
      "v0",
      "issues_graph",
      "get_issue",
      user&.id,
      repository&.owner_id,
      id, # issue/item id
      updated_at.to_i,
    ].join(":")
  end

  # Nested objects need to be converted to hashes before being converted to json to prevent data loss.
  def jsonify_hierarchy_state(issues_graph_response)
    data_hash = issues_graph_response&.data.to_h
    issues_graph_hash = issues_graph_response.to_h
    issues_graph_hash[:data] = data_hash
    issues_graph_hash.to_json
  end

  def async_hierarchy_state(viewer: nil)
    return unless persisted? && tasklist_blocks_enabled?
    return unless GitHub.flipper[:issue_hierarchy_state].enabled?
    GitHub.async_issues_graph_api_client.get_issue(**common_get_issue_options(viewer))
  end

  def common_get_issue_options(viewer)
    modified_age = Time.now - (updated_at || Time.current)
    modified_very_recently = modified_age < LAST_MODIFIED_AT_MIN_AGE_FOR_DENORMALIZED_GET
    feature_symbol = :issues_graph_api_disable_denormalized_read
    disable_denormalized_read = modified_very_recently ||
      repository&.feature_enabled?(feature_symbol) ||
      (viewer && viewer.feature_enabled?(feature_symbol))
    {
      use_denormalized_data: !disable_denormalized_read,
      key: IssuesGraph::Proto::Key.new(
        ownerId: repository&.owner_id,
        itemId: id,
      )
    }
  end

  def remote_tracking_blocks
    hierarchy_state&.tracking&.sort_by(&:order) || false
  end

  def hierarchy_query_type
    hierarchy_state&.queryType || nil
  end

  def hierarchy_response_source_type
    hierarchy_state&.responseSourceType || nil
  end

  def hierarchy_tracked_by
    return @hierarchy_tracked_by if defined?(@hierarchy_tracked_by)
    return @hierarchy_tracked_by = [] unless hierarchy_state&.trackedBy

    @hierarchy_tracked_by = hierarchy_state.trackedBy
      # convert the hierarchy_state.trackedBy to a list of hashes that we expect
      .map { |block| ::TasklistBlocks::Issue.from_proto(issue: block.issues[0]).to_h unless block.issues.empty? }
      # remove any blocks that don't have a parent (i.e. safeguard erroneous data)
      .compact
      # remove any empty issues, which shouldn't be present, but to safeguard against denormalization bugs
      .reject { |issue| issue[:item_id].zero? || issue[:repository_id].zero? }
      # remove any non-unique tracking issues, since the same issue could technically have 2 tracking blocks both
      # tracking this issue
      .uniq { |issue| issue[:item_id] }
  end

  def parent_issues
    return [] unless hierarchy_state&.trackedBy

    hierarchy_state
      .trackedBy
      .flat_map do |block|
        next if block.issues.empty?
        issue = ::TasklistBlocks::Issue.from_tracking_block_proto(tracking_block: block)
        next if issue.issue_id.zero? || issue.repository_id.zero? # safeguard against denormalization bugs
        issue
      end
        .compact
        .uniq(&:issue_id)
  end

  def hierarchy_completion
    TasklistBlocks::Completion.from_proto(completion: hierarchy_state&.issue&.completion) || false
  end

  def compressed_body_tasklist_uuids
    return [] unless compressed_body
    T.must(compressed_body).lines.map do |line|
      # TODO: should this live somewhere more centrally shared? (i.e. in this module?)
      matches = line.match(TasklistBlocks::UrlExpander::TRACKING_BLOCK_URL_REGEX)
      matches["tracking_block_id"] if matches
    end.compact.uniq
  end

  def remote_tasklist_uuids
    return [] unless remote_tracking_blocks

    remote_tracking_blocks.collect do |block|
      block&.key&.primaryKey&.uuid
    end.compact
  end

  def removed_tasklist_uuids
    return @removed_tasklist_uuids if defined?(@removed_tasklist_uuids)

    return [] unless tasklist_blocks_enabled?
    return [] unless body_changed? || body_changed_after_commit?
    return [] unless compressed_body_previously_changed? && compressed_body_previously_was

    @removed_tasklist_uuids = remote_tasklist_uuids - compressed_body_tasklist_uuids
  end

  # Public: Reconciles tracking blocks detected in the issue body with issue graph to establish hierarchy for the issue.
  #
  # Returns nothing.
  def reconcile_tracking_blocks
    return unless GitHub.flipper[:issue_tasklist_block_writes].enabled?
    unless tasklist_blocks_enabled?
      increment("issues.tracking_blocks.reconcile.disabled", tags: ["reason:feature_flag", "subject:owner"])
      return
    end

    GitHub.dogstats.distribution_time("issues.tracking_blocks.reconcile.time") do
      reconcile_removed_tasklist_urls
      reconcile_added_tasklists
    end
  ensure
    @hierarchy_state = nil
  end

  def reconcile_tracking_blocks_after_save
    return unless GitHub.flipper[:issue_tasklist_block_writes].enabled?
    unless tasklist_blocks_enabled?
      GitHub.dogstats.increment("issues.tracking_blocks.reconcile.disabled", tags: ["reason:feature_flag", "subject:owner"])
      return
    end

    GitHub.dogstats.distribution_time("issues.tracking_blocks.reconcile.time") do
      reconcile_added_tasklists do
        tracking_blocks = TasklistBlockCommands::SerializeFromBodyResult.new(
          tasklists: body_result_tasklists
        ).call.data

        model = self.to_hierarchy_model
        raise ::IssuesGraph::Errors::ClientError unless model.present?

        GitHub
          .issues_graph_api_client
          .replace_tracking_blocks_for_parent(
            model,
            tracking_blocks
          )
      end
    end
  ensure
    @hierarchy_state = nil
  end

  def tracking_blocks_should_reconcile_after_commit?
    return false if tasklist_block_markdown_at_rest_enabled?
    tracking_blocks_modified?
  end

  def tracking_blocks_should_reconcile_after_save?
    return false unless tasklist_block_markdown_at_rest_enabled?
    tracking_blocks_added? || tracking_blocks_after_change?
  end

  def reconcile_removed_tasklist_urls
    return unless removed_tasklist_uuids.any?
    GitHub.dogstats.distribution("issues.tracking_blocks.removed.count", removed_tasklist_uuids.length)
    remove_tracking_blocks_for_parent(parent: self, tracking_block_ids: removed_tasklist_uuids)
  end

  def reconcile_added_tasklists
    T.bind(self, Issue)

    unless has_tasklist_blocks?
      increment("issues.tracking_blocks.reconcile.empty")
      return unless block_given?
      return yield
    end

    # Determine average number of tracking blocks included in issues
    GitHub.dogstats.distribution("issues.tracking_blocks.reconcile.count", body_result_tasklists.count)
    tracking_blocks = TasklistBlockCommands::SerializeFromBodyResult.new(
      tasklists: body_result_tasklists
    ).call.data unless block_given?

    # TODO: Add validation error with error response from issues graph
    response = block_given? ? yield : add_tracking_blocks_for_parent(parent: self, tracking_blocks: tracking_blocks)

    # Metrics are created after successful response
    body_result_tasklists.each do |tracking_block|
      tracking_block.items.each do |tracking_block_item|
        case tracking_block_item
        when TasklistBlocks::IssueReference
          increment("issues.tracking_blocks.reconcile.item", tags: ["action:create", "subject:issue"])
        when TrackingBlocks::DraftIssue
          increment("issues.tracking_blocks.reconcile.item", tags: ["action:create", "subject:draft_issue"])
        end
      end
    end

    unless tasklist_block_markdown_at_rest_enabled?
      # Prepare calling HTML pipeline by adding the tracking_blocks context
      body_context = async_body_context.sync.tap do |context|
        context[:tracking_blocks] = response.collect do |primary_key|
          TrackingBlock.new(
            id: primary_key.uuid,
            issue: self,
          )
        end
      end
      result = GitHub::Goomba::BlockFenceInputFilter.new(body_context).replace(compressed_body)

      update_body(result, body_context_user)
    end
  end

  # Public: Determines if the issue supports tracking blocks.
  #
  # Returns true if issue supports tracking blocks, false otherwise.
  def tasklist_blocks_enabled?
    return false unless repository&.owner

    repository&.owner&.feature_enabled?(:tasklist_block)
  end

  def tasklist_block_markdown_at_rest_enabled?
    return false unless repository&.owner

    repository&.owner&.feature_enabled?(:tasklist_block_markdown_at_rest)
  end

  # Public: Determines if the issue body contains tracking blocks within the Markdown.
  #
  # Returns true if issue body contains tracking blocks, false otherwise.
  def has_tasklist_blocks?
    return false unless tasklist_blocks_enabled?

    body_result_tasklists.count > 0
  end

  def body_result_tasklists
    # pull the detected tasklists from the markdown body result
    if GitHub.flipper[:tasklist_block_precache].enabled?(repository&.owner)
      tasklist_blocks = body_result.tasklist_blocks
      return tasklist_blocks if tasklist_blocks.empty?
      tasklist_blocks.values
    elsif GitHub.flipper[:tasklist_block_nested_html_pipeline].enabled?(repository&.owner)
      body_result.tasklist_blocks
    else
      body_result.tracking_blocks
    end
  end

  # Public: Determines tracking blocks have been added to the issue body.
  #
  # Returns true if tracking blocks added to issue, false otherwise.
  def tracking_blocks_added?
    (body_changed? || body_changed_after_commit?) && has_tasklist_blocks?
  end

  def tasklists_removed?
    (body_changed? || body_changed_after_commit?) && removed_tasklist_uuids.any?
  end

  def tracking_blocks_modified?
    tracking_blocks_added? || tasklists_removed?
  end

  def tracking_blocks_after_change?
    ((body_changed? || body_changed_after_commit?) && remote_tasklist_uuids.any?)
  end

  # Private: if the Issues Graph API is enabled, queue a job to sync the data
  # for a given issue to the Issues Graph data store.
  #
  # Returns nothing.
  private def sync_issues_graph_data
    return unless GitHub.issues_graph_api_enabled?(modifying_user)
    return unless hierarchy_model = self.to_hierarchy_model

    SyncIssueToIssuesGraphJob.perform_later(hierarchy_model)
  end

  # Public: Convert an issue to a TasklistBlocks::Issue mapping
  #
  # Returns TasklistBlocks::Issue.
  def to_tasklist_issue
    owner_login, repository_name, _ = repository&.name_with_display_owner.split("/")

    TasklistBlocks::Issue.new(
      title: title,
      state: safe_state,
      issue_id: id,
      url: url,
      number: number,
      repository_id: repository_id,
      repository_name: repository_name,
      owner_id: repository&.owner_id,
      owner_display_login: owner_login,
    )
  end

  # Public: convert a given issue into a hash that the issues-graph service
  # accepts as the "key" of an issue on the graph.
  #
  # Returns a Hash.
  def to_hierarchy_model_key
    {
      ownerId:   repository&.owner_id,
      itemId:  id,
    }
  end

  # Public: convert a given issue into a hash that the issues-graph service
  # accepts as a representation of an issue on the graph.
  #
  # Returns a Hash.
  sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
  def to_hierarchy_model
    repo = repository

    unless repo.present?
      GitHub.logger.info(
        "Issue#to_hierarchy_model returned nil due to missing repository",
        "code.namespace": "Issue::IssuesGraphDependency",
        "code.function": "to_hierarchy_model",
        "gh.issue.id": self.id,
      )
      return nil
    end

    pull_request = self.pull_request
    return pull_request.to_hierarchy_model if pull_request.present? && GitHub.flipper[:tasklist_block].enabled?(repository&.owner)

    nwo = repo.name_with_display_owner.split("/")
    {
      key: to_hierarchy_model_key,
      title: title,
      url: url,
      state: state,
      stateReason: state_reason,
      userName: nwo[0],
      repoName: nwo[1],
      number:   number,
      repoId: repository_id,
      assignees: assignees.map(&:to_hierarchy_model),
      labels: labels.map(&:to_hierarchy_model),
      itemType: ISSUE_ITEM_TYPE,
    }
  end

  # Public: convert a given issue into a hash that we can send down the wire as
  # autocomplete results in the omnibar.
  #
  # Returns a Hash.
  def to_omnibar_result
    {
      id: id,
      number: number,
      url: url,
      state: safe_state.to_sym,
      state_reason: state_reason&.to_sym,
      title: GitHub::Goomba::TitleMarkdownFilter.call(title),
      type: self.pull_request_id ? :pull_request : :issue,
    }.compact
  end

  # Emit events for added tasklist blocks on update.
  #
  # Returns nothing.
  def instrument_tasklist_block_add_on_update
    return yield if spammy?

    tasklists_before = body_result_tasklists.count
    result = yield
    tasklists_after = body_result_tasklists.count

    # Will not instrument if there is no change in the number of tasklists
    tasklists_added = tasklists_after - tasklists_before
    if tasklists_added > 0
      tasklists_added.times do
        instrument_tasklist_block_add(actor: modifying_user, repository: repository, issue: self)
      end
      # Clear memoized value so we don't send double the events
      @tasklists_before = body_result_tasklists.count
    end

    result
  end

  # Emit events for added tasklist blocks on create.
  #
  # Returns nothing.
  def instrument_tasklist_block_add_on_create
    body_result_tasklists.count.times do
      instrument_tasklist_block_add(actor: modifying_user, repository: repository, issue: self)
    end
  end

  # Creates a new tracking block with a child in a parent issue
  def create_tasklist_in_parent(parent:)
    parent_body = parent.body ||= ""
    spacing = parent.body.nil? ? "" : "\n\n"
    parent_body += "#{spacing}\`\`\`[tasklist]\n - [ ] #{repository&.name_with_display_owner}##{id}\n\`\`\`"
    parent.update_body(parent_body, modifying_user)
  end

  # Adds child to existing tracking block in parent issue
  sig { params(owner_id: Integer, parent: Issue, block_id: String).returns(T.any(NilClass, T::Boolean)) }
  def add_to_tasklist_in_parent(owner_id:, parent:, block_id:)
    T.bind(self, Issue)

    response = update_tracking_block_by_key(owner_id: owner_id, block_id: block_id, issues_to_add: [self])
    return false if response&.success

    parent.notify_socket_subscribers
    instrument_tasklist_block_item_add(actor: modifying_user, repository: repository, issue: self, item_type: :ISSUE)
  end

  # Removes child from existing tracking block in parent issue
  def remove_from_tasklist_in_parent(owner_id:, parent:, block_id:, item_uuid:)
    item_to_remove = if item_uuid
      TrackingBlocks::KeyOnlyItem.new(
        owner_id: repository&.owner_id,
        item_id: self.id,
        uuid: item_uuid
      )
    end
    return false unless item_to_remove

    response = update_tracking_block_by_key(owner_id: owner_id, block_id: block_id, issues_to_remove: [item_to_remove])
    return false if response&.success

    parent.notify_socket_subscribers
    instrument_tasklist_block_item_remove(actor: modifying_user, repository: repository, issue: self, item_type: :ISSUE)
  end

  # Create a job to notify tracked by issue's socket subscribers
  def notify_tracked_by_issue
    return unless hierarchy_tracked_by.any?

    tracked_by_ids = hierarchy_tracked_by.map { |tracked_by| tracked_by[:item_id] }
    NotifyTrackedByJob.set(wait_until: NOTIFY_TRACKING_ISSUES_WAIT_TIME.from_now).perform_later(tracked_by_ids)
  end

  # Private: For a given message and array of colon-separated key-value pairs,
  # emit an increment metric.
  #
  # The idea here is to help us correlate our metrics (aggregate data) with more
  # user-level data in logs as we try to understand our metrics better.
  #
  # Returns nothing.
  private def increment(message, tags: [], log_only_fields: {})
    GitHub.dogstats.increment(message, tags: tags)
  end

  # Private: if `state` is nil, return an empty string. Otherwise, return the
  # string value of `state`.
  #
  # This assumes you have preloaded the pull request association on the issue.
  # If you have not please be aware that this method will make a database call
  # and could lead to N+1 queries.
  sig { returns(String) }
  private def safe_state
    return pull_request_safe_state if pull_request_id

    self.state || ""
  end

  # Private: pull requests have state but they also have "reviewable_state"
  # which can incompass draft and other states. This method will return the
  # reviewable_state if the pull request is a draft. Otherwise, it will return
  # the state of the pull request.
  sig { returns(String) }
  private def pull_request_safe_state
    return "" unless pull_request_id

    pull_request&.draft_state? ? "draft" : pull_request&.state.to_s
  end

  attr_accessor :parsed_tasklist_blocks
  sig { void }
  private def track_tasklist_blocks
    return if GitHub.flipper[:disable_track_tasklist_blocks].enabled?
    return unless tasklist_blocks_enabled?
    return diff_parsed_tasklist_blocks if defined?(@parsed_tasklist_blocks)

    self.parsed_tasklist_blocks = normalize_tasklist_blocks_from_pipeline(
      body_result.tasklist_blocks
    )
  end

  sig { returns(T.nilable(TasklistBlockCommands::Result)) }
  private def diff_parsed_tasklist_blocks
    return unless tasklist_blocks_enabled?
    return unless body_tasklist_blocks = body_result&.tasklist_blocks
    body_tasklist_blocks = normalize_tasklist_blocks_from_pipeline(body_tasklist_blocks)

    TasklistBlockCommands::DiffChanges.new(
      tasklist_blocks_previous: Array.wrap(parsed_tasklist_blocks),
      tasklist_blocks_next: Array.wrap(body_tasklist_blocks),
      issue: T.cast(self, Issue),
      actor: modifying_user
    ).call
  end

  # In all features the body_result returns a hash with tasklist blocks as the
  # body. So if we have a hash, normalized the values of the body result to
  # tasklist blocks as an array.
  sig { params(collection: T.any(Hash, Array)).returns(T::Array[TasklistBlock]) }
  private def normalize_tasklist_blocks_from_pipeline(collection)
    collection.is_a?(Hash) ? collection.values : collection
  end
end
