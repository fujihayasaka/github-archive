# typed: true
# frozen_string_literal: true

class AuditLog::ResultsView < AuditLog::IndexPageView
  attr_reader :query
  attr_reader :valid_query
  attr_reader :page
  attr_reader :after
  attr_reader :before
  attr_reader :git_export_enabled
  attr_reader :export_logs_enabled
  attr_reader :feature_flags
  alias_method :git_export_enabled?, :git_export_enabled
  alias_method :export_logs_enabled?, :export_logs_enabled

  def after_initialize
    super
    # Execute query and cache results
    results
    # Everything went well, the query is valid
    @valid_query = true
  rescue Driftwood::TwirpUtil::InvalidArgumentError, ArgumentError
    # User provided an invalid query
    @valid_query = false
  end

  # Public: The audit logs for this user (or org).
  #
  # Returns an Array of Audit::Elastic::Hits.
  def audit_logs
    @audit_logs ||= begin
      entries = normalize(results.results)
      preload_associations(entries)
      entries
    end
  end

  # Public: Check if there are audit logs for this user/org/enterprise account.
  #
  def audit_logs?
    valid_query? && audit_logs.any?
  end

  def normalize(entries)
    AuditLogEntry.new_from_array(entries)
  end

  def preload_associations(entries)
    user_ids = (entries.map(&:user_id) + entries.map(&:actor_id) + entries.map(&:org_id)).flatten.uniq.compact
    user_map = User.where(id: user_ids).includes(:profile).index_by(&:id)

    marketplace_listing_ids = entries.map(&:marketplace_listing_id).uniq.compact
    marketplace_listing_map = Marketplace::Listing.where(id: marketplace_listing_ids).index_by(&:id)

    memex_project_ids = entries.filter_map { |e| e.project_id if e.project_id.present? && e.memex_project? }.uniq.compact
    memex_project_map = MemexProject.where(id: memex_project_ids).index_by(&:id)

    project_ids = entries.filter_map { |e| e.project_id if e.project_id.present? && !e.memex_project? }.uniq.compact
    project_map = Project.where(id: project_ids).index_by(&:id)

    issue_comment_ids = entries.map(&:issue_comment_id).uniq.compact
    issue_comment_map = IssueComment.where(id: issue_comment_ids).index_by(&:id)

    discussion_post_ids = entries.map(&:discussion_post_id).uniq.compact
    discussion_post_map = DiscussionPost.where(id: discussion_post_ids).index_by(&:id)

    discussion_post_reply_ids = entries.map(&:discussion_post_reply_id).uniq.compact
    discussion_post_reply_map = DiscussionPostReply.where(id: discussion_post_reply_ids).index_by(&:id)

    entries.each do |entry|
      user = audit_log_record_for_ids(user_map, entry.user_id)
      actor = audit_log_record_for_ids(user_map, entry.actor_id)
      org = audit_log_record_for_ids(user_map, entry.org_id)

      entry.user_obj = user
      entry.actor_obj = actor
      entry.org_obj = org
      entry.issue_comment = issue_comment_map[entry.issue_comment_id]
      entry.marketplace_listing = marketplace_listing_map[entry.marketplace_listing_id]
      entry.project = entry.memex_project? ? memex_project_map[entry.project_id] : project_map[entry.project_id]
      entry.discussion_post = discussion_post_map[entry.discussion_post_id]
      entry.discussion_post_reply = discussion_post_reply_map[entry.discussion_post_reply_id]
    end
  end

  # Public: The title of the current search or the default title
  #
  # Returns a String
  def search_title
    return "The supplied query is invalid" unless valid_query
    if query
      "Events matching search query"
    else
      "Recent events"
    end
  end

  # Public: Fetch all matching audit log entries matching the organization
  # scoped user query.
  #
  # Returns Array of Audit::Elastic::Hits
  def results
    @results ||= search_query.execute
  end

  def driftwood_results?
    results.is_a?(Driftwood::SearchResults)
  end

  # Public: Whether to show the export results button.
  #
  # Returns a Boolean.
  def show_export_all?
    audit_logs?
  end

  def next_cursor
    if @results.respond_to?(:after_cursor)
      @results.after_cursor
    end
  end

  def prev_cursor
    if @results.respond_to?(:before_cursor)
      @results.before_cursor
    end
  end

  def prev_page?
    if @results.respond_to?(:has_previous_page?)
      @results.has_previous_page?
    end
  end

  def next_page?
    #Driftwood::Results does not have next_page.present?
    if @results.respond_to?(:has_next_page?)
      @results.has_next_page?
    end
  end

  def prev_page_params
    page_params(before: prev_cursor)
  end

  def next_page_params
    page_params(after: next_cursor)
  end

  def yesterdays_activity_query
    "created:#{1.day.ago.strftime("%Y-%m-%d")}"
  end

  def organization_membership_query
    "action:org.invite_member"
  end

  def team_management_query
    "action:team.create action:team.destroy action:team.add_member action:team.remove_member action:team.promote_maintainer action:team.demote_maintainer"
  end

  def repository_management_query
    "action:repo.create action:repo.destroy action:repo.restore action:repo.access action:repo.add_member action: repo.remove_member action:team.add_repository action:team.remove_repository"
  end

  def billing_updates_query
    "action:payment_method action:billing.change_email"
  end

  def document_id(entry)
    entry.hit[:_document_id] || SecureRandom.urlsafe_base64(16)
  end

  def hide_export_buttons?(entity)
    GitHub.flipper[:audit_log_react].enabled?(current_user) &&
    (GitHub.flipper[:audit_log_export_logs].enabled?(current_user) ||
    GitHub.flipper[:audit_log_export_logs].enabled?(entity))
  end
end
