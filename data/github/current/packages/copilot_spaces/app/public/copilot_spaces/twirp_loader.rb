# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  class TwirpLoader
    include GitHub::Memoizer
    LookupValue = T.type_alias { T.any(User, Integer, String) }

    sig do
      params(
        viewer: User,
        cap_filter: ConditionalAccess::Filter,
        filter_individual_spaces: T::Boolean,
        access_control: CopilotAPI::AccessControl,
      ).returns(T::Array[CopilotSpace])
    end
    def self.visible_spaces(viewer:, cap_filter:, filter_individual_spaces:, access_control:)
      copilot_spaces = CopilotSpace.visible_to(viewer, cap_filter).to_a
      copilot_spaces.filter_map do |copilot_space|
        loader = build_loader(
          copilot_space,
          viewer:,
          cap_filter:,
          filter_individual_spaces:,
          skip_readable_by_check: true,
          access_control:,
        )
        loader.space if loader.authorized?
      end
    end

    sig do
      params(
        viewer: User,
        cap_filter: ConditionalAccess::Filter,
        access_control: CopilotAPI::AccessControl,
        custom_copilot_id: T.nilable(T.any(Integer, String)),
        owner: T.nilable(User),
        slug: T.nilable(String),
        name: T.nilable(String),
      ).returns(T.nilable(TwirpLoader))
    end
    def self.find(viewer:, cap_filter:, access_control:, custom_copilot_id: nil, owner: nil, slug: nil, name: nil)
      copilot_space = direct_lookup_scope.find_by(**find_attributes(
        custom_copilot_id:,
        owner:,
        slug:,
        name:,
      ))
      return nil if copilot_space.nil?

      build_loader(copilot_space, viewer:, cap_filter:, access_control:)
    end

    sig do
      params(
        custom_copilot_id: T.nilable(T.any(Integer, String)),
        owner: T.nilable(User),
        slug: T.nilable(String),
        name: T.nilable(String),
      ).returns(T::Hash[Symbol, LookupValue])
    end
    def self.find_attributes(custom_copilot_id: nil, owner: nil, slug: nil, name: nil)
      present_lookup_keys = T.let([], T::Array[Symbol])
      present_lookup_keys << :custom_copilot_id if custom_copilot_id.present?
      present_lookup_keys << :slug if slug.present?
      present_lookup_keys << :name if name.present?

      raise ArgumentError, "expected exactly one lookup key" unless present_lookup_keys.one?

      owner_value = owner
      custom_copilot_id_value = custom_copilot_id
      slug_value = slug
      name_value = name

      case present_lookup_keys.first
      when :custom_copilot_id
        raise ArgumentError, "custom_copilot_id is required for id lookup" if custom_copilot_id_value.blank?

        if owner_value.present?
          { owner: owner_value, number: custom_copilot_id_value }
        else
          { id: custom_copilot_id_value }
        end
      when :slug
        raise ArgumentError, "owner is required for slug lookup" if owner_value.blank?
        raise ArgumentError, "slug is required for slug lookup" if slug_value.blank?

        { owner: owner_value, slug: slug_value }
      when :name
        raise ArgumentError, "owner is required for name lookup" if owner_value.blank?
        raise ArgumentError, "name is required for name lookup" if name_value.blank?

        { owner: owner_value, name: name_value }
      else
        raise ArgumentError, "unsupported lookup"
      end
    end

    sig do
      params(
        viewer: User,
        cap_filter: ConditionalAccess::Filter,
        custom_copilot_id: T.any(Integer, String),
        access_control: CopilotAPI::AccessControl,
        owner: T.nilable(User),
      ).returns(T.nilable(TwirpLoader))
    end
    def self.for_id(viewer:, cap_filter:, custom_copilot_id:, access_control:, owner: nil)
      find(viewer:, cap_filter:, custom_copilot_id:, owner:, access_control:)
    end

    sig do
      params(
        viewer: User,
        cap_filter: ConditionalAccess::Filter,
        owner: User,
        slug: String,
        access_control: CopilotAPI::AccessControl,
      ).returns(T.nilable(TwirpLoader))
    end
    def self.for_slug(viewer:, cap_filter:, owner:, slug:, access_control:)
      find(viewer:, cap_filter:, owner:, slug:, access_control:)
    end

    sig do
      params(
        viewer: User,
        cap_filter: ConditionalAccess::Filter,
        owner: User,
        name: String,
        access_control: CopilotAPI::AccessControl,
      ).returns(T.nilable(TwirpLoader))
    end
    def self.for_name(viewer:, cap_filter:, owner:, name:, access_control:)
      find(viewer:, cap_filter:, owner:, name:, access_control:)
    end

    sig do
      params(
        copilot_space: CopilotSpace,
        viewer: User,
        cap_filter: ConditionalAccess::Filter,
        access_control: CopilotAPI::AccessControl,
        filter_individual_spaces: T::Boolean,
        skip_readable_by_check: T::Boolean,
      ).returns(TwirpLoader)
    end
    def self.build_loader(copilot_space, viewer:, cap_filter:, access_control:, filter_individual_spaces: false, skip_readable_by_check: false)
      new(
        space: assign_user_and_cap(copilot_space, viewer:, cap_filter:),
        viewer:,
        filter_individual_spaces:,
        skip_readable_by_check:,
        access_control:,
      )
    end

    sig do
      params(
        copilot_space: CopilotSpace,
        viewer: User,
        cap_filter: ConditionalAccess::Filter,
      ).returns(CopilotSpace)
    end
    def self.assign_user_and_cap(copilot_space, viewer:, cap_filter:)
      copilot_space.current_user = viewer
      copilot_space.cap_filter = cap_filter
      copilot_space
    end

    sig { returns(ActiveRecord::Relation) }
    def self.direct_lookup_scope
      CopilotSpace.includes(:resources).preload(:owner)
    end

    private_class_method :assign_user_and_cap, :build_loader, :direct_lookup_scope

    sig do
      params(
        space: CopilotSpace,
        viewer: User,
        access_control: CopilotAPI::AccessControl,
        filter_individual_spaces: T::Boolean,
        skip_readable_by_check: T::Boolean,
      ).void
    end
    def initialize(
      space:,
      viewer:,
      access_control:,
      filter_individual_spaces: false,
      skip_readable_by_check: false
    )
      @space = T.let(space, CopilotSpace)
      @viewer = T.let(viewer, User)
      @filter_individual_spaces = T.let(filter_individual_spaces, T::Boolean)
      @skip_readable_by_check = T.let(skip_readable_by_check, T::Boolean)
      @access_control = T.let(access_control, CopilotAPI::AccessControl)
    end

    sig { returns(CopilotSpace) }
    attr_reader :space

    sig { returns(T::Boolean) }
    memoize def authorized?
      return false if filter_individual_spaces && space.owner.user?
      return false if !skip_readable_by_check && !space.readable_by?(viewer)
      return false unless actor_authorized_for_space?

      CopilotSpaces::RepoScopeFilter.authorized?(space: space, viewer: viewer)
    end

    private

    sig { returns(User) }
    attr_reader :viewer

    sig { returns(T::Boolean) }
    attr_reader :filter_individual_spaces, :skip_readable_by_check

    sig { returns(CopilotAPI::AccessControl) }
    attr_reader :access_control

    # Gate access through the same `:get_organization_copilot_space` definition
    # the REST endpoints use. Covers the FGP install-on-org check, the bot
    # `organization_copilot_spaces` permission, and the classic-PAT `read:org`
    # scope in one role.
    sig { returns(T::Boolean) }
    def actor_authorized_for_space?
      return true unless FeatureFlag.vexi.enabled?(:copilot_spaces_twirp_actor_permission_check, viewer, default: false)
      return true if space.owner.user?

      # Web sessions don't carry programmatic permissions; skip the token check.
      return true if viewer.using_auth_via_signed_auth_token?

      # Globally-installed integrations have no org-specific install, so the
      # permission check can never succeed; the client allowlist gates them.
      if viewer.using_auth_via_integration? && viewer.oauth_access&.application&.enabled_global_app?
        return true
      end

      access_control.access_allowed?(:get_organization_copilot_space,
        resource: space,
        current_repo: nil,
        current_org: space.owner,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        raise_on_error: false,
      )
    end
  end
end
