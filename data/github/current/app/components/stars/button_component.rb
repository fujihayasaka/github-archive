# typed: true
# frozen_string_literal: true

module Stars
  class ButtonComponent < ApplicationComponent
    include AnalyticsHelper
    include HydroHelper
    include RepositoryAnalyticsHelper
    include UsersHelper
    include EnterpriseManagedUsersHelper
    include GitHub::Memoizer

    SHOW_COUNT_DEFAULT = false
    SHOW_COUNT_OPTIONS = [SHOW_COUNT_DEFAULT, true]

    BUTTON_BLOCK_DEFAULT = false
    BUTTON_BLOCK_OPTIONS = [BUTTON_BLOCK_DEFAULT, true]

    DISPLAY_DEFAULT = :block
    DISPLAY_OPTIONS = [:none, :block, :inline, :inline_block, :inline_flex, :flex,
      :table, :table_cell].freeze

    BUTTON_CANT_STAR_LABEL = GitHub::HTMLSafeString.make("You can't star at this time")

    CONTEXT_OPTIONS = Star::STARRABLE_CONTEXTS
    DEFAULT_CONTEXT = "other"

    renders_one :list_menu, -> (**system_args) do
      UserListMenuWrapperComponent.new(repository: @repository, system_args: system_args)
    end

    renders_one :starred_state
    renders_one :unstarred_state

    # entity - a Repository, Gist, or Topic to star or unstar
    # context - String describing the request context used to mark how the item was starred in Hydro events.
    #           Must be one of Star::STARRABLE_CONTEXTS. Corresponds to the ContextType enum in Hydro for the entity:
    #           - https://github.com/github/hydro-schemas/blob/0738d0c5747072c2e4d22e83072615a162f15fab/proto/hydro/schemas/github/v1/repository_star.proto#L41
    #           - https://github.com/github/hydro-schemas/blob/9f94d5dca47d467c9aa73e0400799f3c459ed91a/proto/hydro/schemas/github/v1/gist_star.proto#L40
    #           - https://github.com/github/hydro-schemas/blob/0738d0c5747072c2e4d22e83072615a162f15fab/proto/hydro/schemas/github/v1/topic_star.proto#L38
    # hide_text_on_mobile - optional Boolen to hide the button text on mobile
    # hide_text_on_desktop - optional Boolean to hide the button text on desktop
    # button_args - optional Hash of additional Primer system arguments to apply to rendered 'Star' and 'Unstar' buttons
    #               (see https://primer.style/view-components/system-arguments#arguments)
    def initialize(
      entity:,
      context: DEFAULT_CONTEXT,
      show_count: SHOW_COUNT_DEFAULT,
      starred: nil,
      button_block: BUTTON_BLOCK_DEFAULT,
      display: DISPLAY_DEFAULT,
      current_user_can_read_repo: nil,
      hide_text_on_mobile: false,
      hide_text_on_desktop: false,
      override_flex_display: false,
      button_args: {},
      data: {},
      form_flex_class: "flex-auto",
      colorful: false
    )
      unless entity.respond_to?(:starred_by?)
        raise ArgumentError, "#{entity.class.name} must include the Starrable module"
      end

      @entity = entity
      @context = fetch_or_fallback(CONTEXT_OPTIONS, context, DEFAULT_CONTEXT)
      @repository = entity.is_a?(Repository) || entity.is_a?(ExploreFeed::Trending::Repository) ? entity : nil
      @starred = starred
      @button_block = fetch_or_fallback(BUTTON_BLOCK_OPTIONS, button_block, BUTTON_BLOCK_DEFAULT)
      @display = fetch_or_fallback(DISPLAY_OPTIONS, display, DISPLAY_DEFAULT)
      @hide_text_on_mobile = hide_text_on_mobile
      @hide_text_on_desktop = hide_text_on_desktop
      @override_flex_display = override_flex_display
      @current_user_can_read_repo = current_user_can_read_repo
      @button_args = button_args
      @button_classes = @button_args.delete(:classes) || ""
      @data = data
      @user_list_menu_args = user_list_menu_args
      @colorful = colorful
      @form_flex_class = form_flex_class

      if @button_block
        @show_count = false
      else
        @show_count = fetch_or_fallback(SHOW_COUNT_OPTIONS, show_count, SHOW_COUNT_DEFAULT)
      end
    end

    private

    attr_reader :data, :user_list_menu_args

    def render?
      @entity.present? && @context.present?
    end

    def topic_context?
      @context == "topic"
    end

    def container_display
      if show_list_menu? && !@override_flex_display
        :flex
      else
        @display
      end
    end

    def unable_to_star_aria_label
      resource = @repository.nil? ? @entity : @repository
      if emu_contribution_blocked?(resource)
        "You cannot star repositories outside of your enterprise #{enterprise_name}"
      else
        BUTTON_CANT_STAR_LABEL
      end
    end

    def can_star?
      return unless logged_in?

      if @repository
        # For a repository we always want to display the star button in its enabled state. We check the permission
        # on write.
        true
      else
        current_user.can_star?(@entity, is_starred: @starred) && !emu_contribution_blocked?(@entity)
      end
    end

    def is_starred?
      return @starred if @starred != nil
      @starred = logged_in? && @entity.starred_by?(current_user)
    end

    def text_wrapper
      Primer::BaseComponent.new(
        tag: :span,
        display: text_display,
      )
    end

    def colorful?
      @colorful
    end

    memoize def social_count
      @entity.stargazer_count
    end

    memoize def show_social_count?
      @show_count && @repository.nil?
    end

    memoize def show_button_counter?
      @show_count && @repository
    end

    memoize def show_list_menu?
      @repository
    end

    memoize def unstar_confirmation?
      show_list_menu? && logged_in?
    end

    memoize def visual_icon_display
      if @hide_text_on_mobile && @hide_text_on_desktop
        [:none, nil, :none]
      elsif @hide_text_on_desktop
        [:inline_block, nil, :none]
      elsif @hide_text_on_mobile
        [:none, nil, :inline_block]
      else
        :inline_block
      end
    end

    memoize def octicon_display
      if @hide_text_on_mobile && @hide_text_on_desktop
        :inline_block
      elsif @hide_text_on_desktop
        [:none, nil, :inline_block]
      elsif @hide_text_on_mobile
        [:inline_block, nil, :none]
      end
    end

    memoize def text_display
      if @hide_text_on_mobile && @hide_text_on_desktop
        [:none, nil, :none]
      elsif @hide_text_on_desktop
        [:inline, nil, :none]
      elsif @hide_text_on_mobile
        [:none, nil, :inline]
      else
        :inline
      end
    end

    class CounterComponent < ApplicationComponent
      def initialize(repository:, id_suffix:)
        @repository = repository
        @id_suffix = id_suffix
      end

      def call
        render(Primer::Beta::Counter.new(
          id: "repo-stars-counter-#{@id_suffix}",
          count: @repository.stargazer_count,
          round: true,
          limit: nil,
          classes: "js-social-count",
          "aria-label": "#{pluralize(@repository.stargazer_count, "user")} starred this repository",
          "data-singular-suffix": "user starred this repository",
          "data-plural-suffix": "users starred this repository",
          "data-turbo-replace": true
        ))
      end
    end

    # Wrapper around a UserLists::MenuComponent used to ensure that the menu button is assigned a unique DOM ID each
    # time it's rendered.
    #
    # See https://github.com/ViewComponent/view_component/issues/1038.
    class UserListMenuWrapperComponent < ApplicationComponent
      def initialize(repository:, system_args:)
        @repository = repository
        @system_args = system_args
      end

      def with_id_suffix(suffix)
        UserLists::MenuComponent.new(
          id_suffix: suffix,
          repository: @repository,
          **@system_args,
        )
      end

      def call
        render(UserLists::MenuComponent.new(
          repository: @repository,
          **@system_args,
        ))
      end
    end
  end
end
