# typed: true
# frozen_string_literal: true

module TimelineHelper
  include CommentsHelper
  include AvatarHelper
  include BotHelper

  DEFAULT_PAGE_SIZE = 60
  THUMBS_UPS = %w(:+1: +1 👍 👍🏻 👍🏼 👍🏽 👍🏾 👍🏿).freeze

  def comments_are_similar?(node_a, node_b)
    comment_a = node_a.body&.strip

    comment_b = node_b.body&.strip

    if comment_a.nil? || comment_b.nil?
      return false
    end

    comment_a == comment_b || (THUMBS_UPS.include?(comment_a) && THUMBS_UPS.include?(comment_b))
  end

  # Public: Group Array of GraphQL nodes by their types.
  #
  # Only groups consecutive nodes together that have the same type.
  # Some types of node will always end up in their own, lonely group.
  #
  # nodes - Array of GraphQL nodes
  #
  # Returns Array<Array> of nodes
  def group_timeline_nodes(nodes, group_repeated_comments: false)
    nodes.chunk_while do |node_before, node_after|
      case node_before
      when PullRequest::Adapter::PullRequestReviewAdapter,
        # These nodes are never grouped
        false
      when PlatformTypes::PullRequestReview,
           PlatformTypes::PullRequestReviewThread,
           PlatformTypes::PullRequestCommitCommentThread,
        # These nodes are never grouped
        false
      when PlatformTypes::IssueComment, Issue::Adapter::CommentAdapter
        next unless group_repeated_comments
        # Repeated comments get grouped together
        comments_are_similar?(node_before, node_after) if node_after.is_a?(PlatformTypes::IssueComment)
      when node_after.class
        # Group consecutive nodes of the same type
        true
      when PlatformTypes::TimelineEvent, Issue::Adapter::TimelineEventAdapter
        # Group timeline events together
        node_after.is_a?(PlatformTypes::TimelineEvent)
      else
        # Otherwise we start a new group
        false
      end
    end.to_a
  end

  def count_to_range(total_count)
    case total_count
    when nil then "nil"
    when 0 then "0"
    when 1..9 then "1-9"
    when 10..29 then "10-29"
    when 30..59 then "30-59"
    when 60..119 then "60-119"
    when 120..299 then "120-299"
    else "300+"
    end
  end

  def track_query_execution(query_name, additional_tags = [])
    before_query_count = GitHub::MysqlInstrumenter.query_count
    timer = Timer.start
    issue_node = yield
    timer.stop
    after_query_count = GitHub::MysqlInstrumenter.query_count

    if issue_node.is_a?(Issue::Adapter::IssueAdapter)
      total_count = issue_node.timeline.total_count
      # TODO issue_timeline: adjust this to timeline start and end
      timeline_start_nodes = []
      timeline_end_nodes = []
    else
      issue_hash = issue_node.to_h
      total_count = issue_hash.dig(:timeline, :totalCount)
      timeline_start_nodes = issue_hash.dig(:timelineStart, :nodes)
      timeline_end_nodes = issue_hash.dig(:timelineEnd, :nodes)
    end

    if !total_count.nil?
      additional_tags += ["#{GitHub::TaggingHelper::EMPTY_ISSUE_TAG}:#{total_count == 0}"]
    end
    combined_tags = query_range_tags(total_count, timeline_start_nodes, timeline_end_nodes).concat(additional_tags).uniq
    GitHub.dogstats.distribution("issue_#{ query_name }_query_execute.dist.time", timer.elapsed_ms, tags: combined_tags)
    total_query_count = after_query_count - before_query_count
    GitHub.dogstats.distribution("issue_#{ query_name }_query_execute.dist.query_count", total_query_count, tags: combined_tags)
    issue_node
  end

  def cached_linked_avatar(author = nil)
    if author
      linked_avatar_for_author(author)
    else
      linked_avatar_for_ghost
    end
  end

  def cached_dependabot_avatar
    @cached_dependabot_avatar ||= avatar_for(
      GitHub.dependabot_github_app.owner,
      20,
      class: "avatar avatar-child rounded-2",
    )
  end

  def cached_event_actor(raw_actor)
    @event_actor ||= Hash.new
    @event_actor[raw_actor.login] ||= event_actor(raw_actor)
  end

  # resolve the cursors to ensure they are valid so we can deliver the proper error to users if they are not.
  def valid_cursors?(before, after)
    before && Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(before)
    after && Platform::ConnectionWrappers::CursorGenerator.resolve_cursor(after)
    true
  rescue Platform::Errors::Cursor
    false
  end

  private

  def query_range_tags(total_count, timeline_start_nodes, timeline_end_nodes)
    total_count = count_to_range(total_count)
    total_range_tag = total_count.nil? ? [] : ["range:#{ count_to_range(total_count.to_i) }"]
    timeline_start_tags = node_range_tags("timeline_start", timeline_start_nodes)
    timeline_end_tags = node_range_tags("timeline_end", timeline_end_nodes)
    total_range_tag.concat(timeline_start_tags, timeline_end_tags)
  end

  def node_range_tags(tag_prefix, timeline_nodes = nil)
    timeline_nodes ||= []
    timeline_nodes
    .reject { |node| node.nil? }
    .group_by { |node| node[:__typename] }
    .map { |node_type, group| "#{ tag_prefix }_range:#{ node_type }:#{ count_to_range(group.size) }" }
  end

  def linked_avatar_for_ghost
    @linked_avatar_for_ghost ||= T.unsafe(self).linked_avatar_for(
      User.ghost,
      40,
      img_class: "avatar rounded-2",
    )
  end

  def linked_avatar_for_author(raw_author)
    @linked_avatar_for_author ||= Hash.new
    @linked_avatar_for_author[raw_author.login] ||= linked_avatar(raw_author)
  end

  def linked_avatar(raw_author)
    T.unsafe(self).linked_avatar_for(
      raw_author,
      40,
      img_class: "avatar rounded-2",
    )
  end

  def event_actor(raw_actor)
    avatar = T.unsafe(self).linked_avatar_for(raw_actor, 20, img_class: "avatar")
    profile_link = T.unsafe(self).profile_link(raw_actor, class: "author Link--primary text-bold")
    bot_tag = bot_identifier(raw_actor)
    avatar + "\n" + profile_link + "\n" + bot_tag.to_s + "\n"
  end
end
