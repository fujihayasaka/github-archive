# typed: true
# frozen_string_literal: true

class RepositoryAdvisory::Adapter::CommentAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::Reactable,
    PlatformTypes::Updatable,
    PlatformTypes::UpdatableComment,
    PlatformTypes::Deletable,
    PlatformTypes::MayBeInternal,
    PlatformTypes::RepositoryNode
  ].freeze

  # object/comments
  attr_reader :database_id
  attr_reader :id
  attr_reader :input_name

  # interfaces/reactable
  attr_reader :reaction_groups
  attr_reader :reaction_path
  attr_reader :viewer_can_react

  # interfaces/comment
  attr_reader :authored_by_subject_author
  attr_reader :subject_id
  attr_reader :subject_type
  attr_reader :author
  attr_reader :body
  attr_reader :body_html
  attr_reader :body_version
  attr_reader :last_edited_at
  attr_reader :last_user_content_edit
  attr_reader :published_at
  attr_reader :viewer_did_author

  attr_reader :advisory_ghsa_id
  attr_reader :repository
  attr_reader :author_to_repo_owner_sponsorship

  delegate :async_viewer_can_read_user_content_edits?, :async_latest_user_content_edit, :minimized?,
    :global_relay_id, :user, :async_user, :user_id, :created_at, :prelude_viewer_can_react, :reactions,
    :prelude_user_logins_by_reaction, :author_association_symbol,
    :report_count, :top_report_reason, :last_reported_at, to: :@object

  def initialize(context, comment)
    super(context)

    viewer = context.viewer
    advisory = context.advisory
    @advisory_ghsa_id = advisory.ghsa_id
    @repository = context.repository_adapter

    @object = comment # comment is a `RepositoryAdvisoryComment`

    @viewer_did_author = (viewer && @object.user_id == viewer.id) || false
    @published_at = @object.created_at

    @spammy = @object.user_is_spammy(viewer)

    @body = @object.body
    @body_version = @object.body_version
    @viewer_can_react = @object.viewer_can_react?(viewer)
    @body_html = @object.body_html

    @author = @object.user
    @authored_by_subject_author = advisory.user_id == @object.user_id

    if @object.viewer_can_read_user_content_edits?(viewer) && @object.latest_user_content_edit
      @last_user_content_edit = Issue::Adapter::UserContentEditAdapter.new(context, user_content_edit: @object.latest_user_content_edit)
    end

    @last_edited_at = @last_user_content_edit&.edited_at

    @database_id = comment.id
    @id = @object.global_relay_id
    @subject_id = advisory.global_relay_id
    @input_name = "repository_advisory_comment"

    @subject_type = "advisory"

    # reactions
    @reaction_groups = @object.reaction_groups.inject([]) { |reactions, g| reactions << Issue::Adapter::ReactionGroupAdapter.new(context, reaction_group: g) }
    @reaction_path = @object.reaction_path
  end

  # List of allowed emotions
  #
  # Returns enumerable collection of Emotion objects
  def emotions
    @_emotions ||= @object.class.emotions
  end

  def viewer_can_update
    return @viewer_can_update if defined?(@viewer_can_update)
    @viewer_can_update = @object.viewer_can_update?(@context.viewer)
  end

  def viewer_can_update?
    viewer_can_update
  end

  def viewer_did_author?
    @viewer_did_author
  end

  def viewer_can_react?
    @viewer_can_react
  end

  def raw_object
    @object
  end

  def spammy?
    @spammy
  end

  # This will always be false, copying the logic from `platforms/objects/repository_advisory`
  def created_via_email?
    false
  end
  alias :created_via_email :created_via_email?

  def stafftools_url
    nil
  end

  def is_internal?
    @object.internal?
  end

  def viewer_can_see_delete_button?
    @context.viewer&.site_admin? &&
      @object.viewer_can_delete?(@context.viewer) &&
      @object.repository.pushable_by?(@context.viewer)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
