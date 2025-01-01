# typed: true
# frozen_string_literal: true

# Public: Repository functionality to support the Discussions feature
# (note, this is not Team Discussions).
#
# Slack: #discussions
# Repo: github/discussions
# Team: @github/discussions-reviewers
module Repository::DiscussionsDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include Configurable::DiscussionsEnablement

  requires_ancestor { Repository }

  MINIMUM_ISSUE_COUNT = 5

  included do
    T.bind(self, T.class_of(Repository))

    has_one :organization_discussion, class_name: "OrganizationDiscussionConfig", required: false
    has_many :applied_discussion_labels

    has_many :discussions
    destroy_dependents_in_background :discussions

    # No need to destroy comments when repository is destroyed.
    # They are destroyed in background when discussion is destroyed.
    has_many :discussion_comments

    has_many :discussion_categories, -> { order(:slug) }
    destroy_dependents_in_background :discussion_categories

    has_many :discussion_sections, -> { order(:slug) }
    destroy_dependents_in_background :discussion_sections

    has_many :discussion_spotlights, -> { order(:position) }
    destroy_dependents_in_background :discussion_spotlights
  end

  # Public: Get a timestamp indicating when the specified user last viewed the Discussions
  # tab for this repository.
  #
  # user - a User
  #
  # Returns a DateTime or nil.
  sig { params(user: T.untyped).returns(T.untyped) }
  def discussions_last_viewed_for(user)
    key = discussions_last_viewed_for_key(user)
    timestamp = Discussions::Kv.store.get(key).value { nil }
    return unless timestamp

    begin
      DateTime.iso8601(timestamp)
    rescue ArgumentError, TypeError
      Discussions::Kv.store.del(key)
      nil
    end
  end

  # Public: Get a key used to store the time at which the specified user last viewed the
  # Discussions tab of this repository.
  sig { params(user: User).returns(String) }
  def discussions_last_viewed_for_key(user)
    "discussions-view-#{id}-#{user.id}"
  end

  # Public: Record the current timestamp for the given user as the time at which they
  # last viewed the Discussions tab for this repository.
  sig { params(user: User).void }
  def update_discussions_last_viewed_for(user)
    key = discussions_last_viewed_for_key(user)
    timestamp = Time.zone.now.utc.iso8601
    Discussions::Kv.store.set(key, timestamp)
  end

  # Public: Is the Discussions feature active for this repository?
  sig { returns T::Boolean }
  def discussions_active?
    eligible_for_discussions? && discussions_on?
  end

  # Public: Is the Discussions feature active for this repository?
  sig { returns Promise[T::Boolean] }
  def async_discussions_active?
    return Promise.resolve(T.let(false, T::Boolean)) unless eligible_for_discussions?
    T.unsafe(self).async_discussions_on?
  end

  # Public: Has this repository ever had the Discussions feature turned on, regardless of whether or not it is
  # turned on now?
  sig { returns T::Boolean }
  def discussions_ever_active?
    eligible_for_discussions? && discussions_ever_on?
  end

  # Public: Should we show the Discussions landing page for this repo to this user?
  sig { params(viewer: T.untyped).returns(T.untyped) }
  def show_landing_page?(viewer)
    return false unless viewer
    return @show_landing_page[viewer] if defined? @show_landing_page[viewer]

    @show_landing_page ||= Hash.new
    @show_landing_page[viewer] = public? &&
      !discussions_ever_active? &&
      !viewer.dismissed_repository_notice?("discussions_tab", repository_id: id) &&
      can_toggle_discussions_setting?(viewer) &&
      unboxing_minimum_issue_count?(self.open_issue_count_for(viewer))
  end

  sig { params(open_issue_count: T.untyped).returns(T.untyped) }
  def unboxing_minimum_issue_count?(open_issue_count)
    open_issue_count >= MINIMUM_ISSUE_COUNT
  end

  # Public: Does this repository meet our requirements for access to the discussions feature? This is used to gate
  # visibility of the "Discussions" checkbox in repository settings.
  sig { returns T::Boolean }
  def eligible_for_discussions?
    GitHub.discussions_available_on_platform?
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def instrument_discussion_enablement(actor:)
    GlobalInstrumenter.instrument "repository.enable_discussions", repository: self, actor: actor
  end

  sig { void }
  def discussions_were_enabled
    synchronize_discussions_search_index
    populate_initial_discussion_categories
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def instrument_discussion_disablement(actor:)
    GlobalInstrumenter.instrument "repository.disable_discussions", repository: self, actor: actor
  end

  sig { void }
  def discussions_were_disabled
    synchronize_discussions_search_index
  end

  # Public: Asynchronously determine if more than read access is required to
  # create discussions in this repository.
  #
  # Note this is for the Discussion model, not team discussions.
  #
  # Returns a Promise that resolves to a Boolean.
  sig { returns(T.untyped) }
  def async_discussion_creation_requires_explicit_permission?
    # User-owned repos always support creating discussions if you only have
    # read access to the repository.
    # Check organization_id here to avoid an unnecessary Organization load attempt.
    return Promise.resolve(false) unless organization_id.present?

    async_organization.then do |organization|
      # Check if the organization that owns this repository requires more
      # than read access to create discussions
      organization && !organization.readers_can_create_discussions?
    end
  end

  # Public: Determine if more than read access is required to create
  # discussions in this repository.
  #
  # Note this is for the Discussion model, not team discussions.
  #
  # Returns a Boolean.
  sig { returns(T.untyped) }
  def discussion_creation_requires_explicit_permission?
    async_discussion_creation_requires_explicit_permission?.sync
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_can_toggle_discussions_setting?(actor)
    return Promise.resolve(false) unless actor
    return Promise.resolve(false) unless eligible_for_discussions?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :manage_settings_discussions,
      actor: actor.ability_delegate,
      subject: self,
      context: { "action.programmatic_access_level": Permission.actions[:write] },
    ).then { |decision| decision.allow? }
  end

  # Public: Can the given user enable or disable Discussions in this repository?
  #
  # actor - a User
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def can_toggle_discussions_setting?(actor)
    async_can_toggle_discussions_setting?(actor).sync
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def can_convert_issues_to_discussions?(actor)
    return false unless actor.present?

    ::Permissions::Enforcer.authorize(
      action: :convert_issues_to_discussions,
      actor: actor,
      subject: self,
    ).allow?
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_can_convert_issues_to_discussions?(actor)
    return false unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :convert_issues_to_discussions,
      actor: actor,
      subject: self,
    ).then { |decision| decision.allow? }
  end

  # Public: Populate this repo with an initial list of DiscussionCategories.
  sig { returns(T.untyped) }
  def populate_initial_discussion_categories
    return if discussion_categories.any?
    discussion_categories.create!(DiscussionCategory.initial_categories)
  end

  # Public: Select the available discussion categories for this repository based on the actor's permissions.
  #
  # can_create_discussion_announcements - Boolean or nil. If specified, skip the authz check for announcement
  #   visibility.
  sig { params(actor: T.untyped, can_create_discussion_announcements: T.untyped).returns(T.untyped) }
  def available_discussion_categories_for_actor(actor, can_create_discussion_announcements: nil)
    include_announcements = if can_create_discussion_announcements.nil?
      can_create_discussion_announcements?(actor)
    else
      can_create_discussion_announcements
    end

    categories = available_discussion_categories
    categories = categories.where(supports_announcements: false) unless include_announcements
    categories
  end

  # Public: Select the available discussion categories for this repository.
  sig { returns(T.untyped) }
  def available_discussion_categories
    @available_discussion_categories ||= discussion_categories
  end

  # Public: Determine whether or not Discussions-related features should be
  # available to a given user on this repository. Only accounts for
  # per-repository configuration now that discussions is in public beta for
  # public repos.
  #
  # user - The currently viewing user. Nil for anonymous access.
  #
  # Returns a boolean.
  sig { returns(T.untyped) }
  def show_discussions?
    discussions_on?
  end

  # Public: Locate a category to use in situations where a user was not able to manually specify the category they
  # want a Discussion to be moved to.
  #
  # Prefers a category associated with the current repository called GENERAL_NAME, if one exists. Otherwise, returns
  # an arbitrary category associated with the current repository. Raises an exception if no such DiscussionCategories
  # are available.
  #
  # Returns a DiscussionCategory.
  sig { returns(T.untyped) }
  def fallback_discussion_category!
    discussion_categories.find_by(name: DiscussionCategory::GENERAL_NAME) || discussion_categories.take!
  end

  # Public: Creates or uses the default category for team post to discussions migration
  sig { returns(T.untyped) }
  def team_post_category!
    T.unsafe(discussion_categories).retry_on_find_or_create_error do
      discussion_categories.find_by(DiscussionCategory::COMPATIBLE_EXISTING_TEAM_POST_MIGRATION_CATEGORY) || discussion_categories.create!(DiscussionCategory::TEAM_POST_MIGRATION_CATEGORY)
    end
  end

  sig { params(actor: T.untyped).returns(T.untyped) }
  def discussions_metadata_readable_by?(actor)
    response = ::Permissions::Enforcer.authorize(
      action: :read_discussion_metadata,
      actor: actor,
      subject: self
    )
    response.allow?
  end

  # Public: Can an actor create announcement discussions for this repository?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def can_create_discussion_announcements?(actor)
    async_can_create_discussion_announcements?(actor).sync
  end

  # Public: Can an actor create announcement discussions for this repository, determined asynchronously?
  #
  # actor - The User to check permissions for.
  #
  # Returns a Promise that resolves to a Boolean.
  sig { params(actor: T.untyped).returns(T.untyped) }
  def async_can_create_discussion_announcements?(actor)
    return Promise.resolve(false) unless actor.present?

    Platform::Loaders::Permissions::BatchAuthorize.load(
      action: :create_discussion_announcement,
      actor: actor,
      subject: self,
    ).then { |decision| decision.allow? }
  end

  sig { params(viewer: T.untyped, can_manage_spotlights: T.untyped).returns(T.untyped) }
  def show_discussions_spotlight_popover?(viewer, can_manage_spotlights: false)
    @show_discussions_spotlight_popover_by_args ||= {}
    args_key = "#{viewer}-#{can_manage_spotlights}"
    if @show_discussions_spotlight_popover_by_args.key?(args_key)
      return @show_discussions_spotlight_popover_by_args[args_key]
    end
    @show_discussions_spotlight_popover_by_args[args_key] = can_manage_spotlights &&
      public? &&
      !viewer&.dismissed_repository_notice?("discussions_tab", repository_id: id) &&
      !viewer&.dismissed_repository_notice?("discussions_spotlight", repository_id: id)
  end

  sig { params(viewer: T.untyped, can_toggle_discussions_setting: T.untyped).returns(T.untyped) }
  def show_discussions_categories_popover?(viewer, can_toggle_discussions_setting: false)
    can_toggle_discussions_setting &&
      public? &&
      !viewer&.dismissed_repository_notice?("discussions_tab", repository_id: id) &&
      !viewer&.dismissed_repository_notice?("discussions_categories", repository_id: id)
  end

  sig { params(viewer: T.untyped, can_toggle_discussions_setting: T.untyped).returns(T.untyped) }
  def show_discussions_new_discussion_popover?(viewer, can_toggle_discussions_setting: false)
    return false unless viewer
    @show_discussions_new_discussion_popover_by_args ||= {}
    args_key = "#{viewer.id}_#{can_toggle_discussions_setting}"
    if @show_discussions_new_discussion_popover_by_args.key?(args_key)
      return @show_discussions_new_discussion_popover_by_args[args_key]
    end
    @show_discussions_new_discussion_popover_by_args[args_key] = can_toggle_discussions_setting &&
      public? &&
      !discussions.any? &&
      !viewer.dismissed_repository_notice?("discussions_tab", repository_id: id) &&
      !viewer.dismissed_repository_notice?("discussions_new_discussion", repository_id: id)
  end

  sig { returns DiscussionTemplates }
  def discussion_templates
    @discussion_templates ||= DiscussionTemplates.new(T.cast(self, Repository)) # rubocop:todo GitHub/AvoidCast
  end

  # Public: Discussion templates for this repository, either from the local repository
  #         or a global health files repository for an organization.
  sig { returns T.nilable(DiscussionTemplates) }
  def preferred_discussion_templates
    @preferred_discussion_templates ||= async_preferred_discussion_templates.sync
  end

  # Public: Discussion templates for this repository, either from the local repository
  #         or a global health files repository for an organization.
  sig { returns Promise[T.nilable(DiscussionTemplates)] }
  def async_preferred_discussion_templates
    if discussion_templates.any? || global_health_files_repository?
      GitHub.dogstats.increment("discussion_templates_lookup", tags: ["location:repository"])
      Promise.resolve(discussion_templates)
    else
      async_global_health_files_repo.then do |global_repository|
        next discussion_templates unless global_repository.present?

        global_templates = global_repository.discussion_templates
        if global_templates.any?
          GitHub.dogstats.increment("discussion_templates_lookup", tags: ["location:global"])
          global_templates
        else
          discussion_templates
        end
      end
    end
  end

  # Public: Does this repository have the maximum number of allowed discussion categories?
  sig { returns T::Boolean }
  def has_max_categories?
    category_count = discussion_categories.count

    if category_count >= DiscussionCategory::MAX_CATEGORIES_PER_REPO
      override_count = DiscussionCategory::LimitOverride.for(self)
      return false if override_count.present? && override_count >= category_count
      return true
    end

    false
  end

  # Public: If this repository is associated with org-level discussions, remove it.
  sig { returns T::Boolean }
  def disassociate_from_org_level_discussions
    # Look up record by repository ID, since it is possible that the repository has been transferred
    # and we don't have the association on the new owner.
    discussion_record = OrganizationDiscussionConfig.where(
      "repository_id = :repo_id",
      repo_id: id,
    ).first
    return true unless discussion_record.present?

    if discussion_record.repository_id == id
      discussion_record[:repository_id] = nil
    end

    if discussion_record.repository_id.nil?
      # If this repository was configured, destroy the whole record.
      discussion_record.destroy
      discussion_record.destroyed?
    else
      discussion_record.save
    end
  end

  sig { returns T::Boolean }
  def sparkle_votes_enabled?
    return true if feature_enabled?(:sparkle_votes)
    owner = self.owner
    return false unless owner
    owner.feature_enabled?(:sparkle_votes)
  end

  sig { returns T::Boolean }
  def org_discussion_source?
    organization_discussion = self.organization_discussion
    return false unless organization_discussion.present?
    organization_discussion.repository_id == id
  end

  private

  def visible_discussions?(viewer = nil)
    discussions.filter_spam_for(viewer).exists?
  end
end
