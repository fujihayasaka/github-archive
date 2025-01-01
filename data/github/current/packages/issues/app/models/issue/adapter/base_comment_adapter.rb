# typed: true
# frozen_string_literal: true

class Issue::Adapter::BaseCommentAdapter < Issue::Adapter::Base
  include GitHub::ResilienceMixin

  TYPES = [
    PlatformTypes::AbuseReportable,
    PlatformTypes::OrgBlockable,
    PlatformTypes::Reactable,
    PlatformTypes::Reportable,
    PlatformTypes::RepositoryNode,
    PlatformTypes::Updatable,
    PlatformTypes::UpdatableComment,
  ].freeze

  # object
  attr_reader :repository

  # Sponsors
  attr_reader :author_to_repo_owner_sponsorship

  # interfaces/reactable
  attr_reader :reaction_groups
  attr_reader :reaction_path
  attr_reader :viewer_can_react

  delegate :author_association_symbol, :prelude_viewer_can_react, :prelude_user_logins_by_reaction, :reactions, :minimized?, to: :@object

  # PerformableViaApp
  attr_reader :via_app

  # AbuseReportable
  attr_reader :last_reported_at
  attr_reader :report_count
  attr_reader :top_report_reason

  # interfaces/comment
  attr_reader :author
  attr_reader :body
  attr_reader :body_html
  attr_reader :body_version
  attr_reader :last_edited_at
  attr_reader :last_user_content_edit
  attr_reader :published_at
  attr_reader :viewer_did_author

  def initialize(context, object:)
    super(context)

    issue = context.issue
    viewer = context.viewer

    @object = object
    @repository = context.repository_adapter

    @viewer_did_author = (viewer && @object.user_id == viewer.id) || false
    @published_at = @object.created_at

    @spammy = @object.user_is_spammy(viewer)

    @body = @object.body
    @body_version = @object.body_version
    @viewer_can_react = with_database_error_fallback(fallback: false) do
      @object.viewer_can_react?(viewer)
    end
    @body_html = @object.body_html

    if @object.viewer_can_read_user_content_edits?(viewer) && @object.latest_user_content_edit
      @last_user_content_edit = Issue::Adapter::UserContentEditAdapter.new(context, user_content_edit: @object.latest_user_content_edit)
    end

    @last_edited_at = @last_user_content_edit&.edited_at

    if viewer.try(:site_admin?)
      @report_count = @object.report_count
      @top_report_reason = @object.top_report_reason
      @last_reported_at = @object.last_reported_at
    end

    app = context.integrations_by_model[@object]
    @via_app = Issue::Adapter::AppAdapter.new(context, app: app) if app

    @reaction_groups = @object.reaction_groups.inject([]) { |reactions, g| reactions << Issue::Adapter::ReactionGroupAdapter.new(context, reaction_group: g) }
    @reaction_path = @object.reaction_path

    if GitHub.sponsors_enabled? && context.author_to_repo_owner_sponsorships_by_author_id.present?
      @author_to_repo_owner_sponsorship = context.author_to_repo_owner_sponsorships_by_author_id[@object.user_id]
    end
  end

  # List of allowed emotions
  #
  # Returns enumerable collection of Emotion objects
  def emotions
    @_emotions ||= @object.class.emotions
  end

  # interfaces/updateable
  def viewer_can_update
    return @viewer_can_update if defined?(@viewer_can_update)
    @viewer_can_update = @object.viewer_can_update?(@context.viewer)
  end

  def viewer_can_update?
    viewer_can_update
  end

  def raw_object
    @object
  end

  def viewer_did_author?
    @viewer_did_author
  end

  def viewer_can_react?
    @viewer_can_react
  end

  def show_first_contribution_prompt?(_)
    # not applicable to issue/comments
    false
  end

  def spammy?
    @spammy
  end

  def via_app?
    @via_app
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
