# typed: true
# frozen_string_literal: true

module Primer
  module Experimental
    # Use select menus to list clickable choices, allow filtering between them, and highlight
    # which ones are selected.
    class SelectMenuComponent < Primer::Component # rubocop:disable ViewComponent/EncouragePreviewsForPrimer
      DEFAULT_ALIGN_RIGHT = false

      MENU_DEFAULTS = {
        tag: :div,
        classes: nil,
      }.freeze

      MODAL_DEFAULTS = {
        classes: nil,
      }.freeze

      DETAILS_DEFAULTS = {
        overlay: Primer::Beta::Details::NO_OVERLAY,
        reset: true,
        classes: nil,
      }.freeze

      renders_one :summary, Primer::Experimental::SelectMenu::SummaryComponent
      renders_one :header, ->(**kwargs) { Primer::Experimental::SelectMenu::HeaderComponent.new(**T.unsafe({ select_menu_id: @select_menu_id, **kwargs })) }
      renders_one :clear_item, ->(**kwargs) { Primer::Experimental::SelectMenu::ItemComponent.new(is_clear_item: true, selected: false, icon: false, **kwargs) }
      renders_one :filter, ->(**kwargs) do
        T.bind(self, Primer::Experimental::SelectMenuComponent)
        Primer::Experimental::SelectMenu::FilterComponent.new(**T.unsafe({ list_id: list_id_for(1), **kwargs }))
      end
      renders_one :footer, Primer::Experimental::SelectMenu::FooterComponent
      renders_many :lists, ->(**kwargs) do
        T.bind(self, Primer::Experimental::SelectMenuComponent)

        @list_count += 1
        role = @menu[:tag] == :"details-menu" ? "listbox" : nil
        Primer::Experimental::SelectMenu::ListComponent.new(id: list_id_for(@list_count), label: @menu[:label], list_role: role, **kwargs)
      end

      # @param align_right [Boolean] Align the whole menu to the right or not.
      # @param will_have_tabs [Boolean] If the content returned by menu[:src] (if present) will have tabs.
      #
      # @param details[:overlay] [Symbol] Options are `:none`, `:default`, and `:dark`. Dictates the type of overlay to render with.
      # @param details[:classes] [String] CSS classes to apply to the details element.
      #
      # @param selected_list_index [Integer] zero-based index of the list to have initially shown, if there are tabs;
      #                                      defaults to the first list
      # @param menu[:classes] [String] CSS classes to apply to the `.SelectMenu` element.
      # @param menu[:src] [String] A URI from which the menu's content can be fetched.
      # @param menu[:tag] [Symbol] HTML element type for the `.SelectMenu` tag; defaults to `:div`, could also use `:"details-menu"`.
      # @param menu[:params] [Hash] Additional arguments to pass directly to the `.SelectMenu` element.
      # @param menu[:label] [String] An accessible label for the menu.
      #
      # @param modal[:classes] [String] CSS classes to apply to the `.SelectMenu-modal` element.
      # @param modal[:params] [Hash] Additional arguments to pass directly to the `.SelectMenu-modal` element.
      #
      # @param system_arguments [Hash] <%= link_to_system_arguments_docs %>
      def initialize(
        align_right: DEFAULT_ALIGN_RIGHT,
        will_have_tabs: false,
        menu: {},
        modal: {},
        details: {},
        selected_list_index: 0,
        **system_arguments
      )
        @align_right = fetch_or_fallback_boolean(align_right, DEFAULT_ALIGN_RIGHT)
        @will_have_tabs = menu[:src].present? && will_have_tabs

        @menu = MENU_DEFAULTS.merge(menu)
        @modal = MODAL_DEFAULTS.merge(modal)
        @details = DETAILS_DEFAULTS.merge(details)
        @selected_list_index = selected_list_index
        @select_menu_id = system_arguments[:id] || "select-menu-#{SecureRandom.uuid}"
        @list_count = 0

        @system_arguments = system_arguments
        overlay_option = fetch_or_fallback(
          Primer::Beta::Details::OVERLAY_MAPPINGS.keys, @details[:overlay], Primer::Beta::Details::NO_OVERLAY
        )
        @system_arguments[:tag] = :details
        @system_arguments[:classes] = class_names(
          @system_arguments[:classes],
          Primer::Beta::Details::OVERLAY_MAPPINGS[overlay_option],
          "details-reset" => @details[:reset],
          @details[:classes] => details[:classes].present?,
        )
      end

      def render?
        return false unless summary.present?

        @menu[:src].present? || lists.any? || content.present? || footer.present? || header.present?
      end

      private

      attr_reader :selected_list_index

      def list_id_for(i)
        "#{@select_menu_id}-list-#{i}"
      end

      def details_component
        Primer::BaseComponent.new(**T.unsafe({ id: @select_menu_id, **@system_arguments }))
      end

      def select_menu_component
        role = "dialog" if @menu[:tag] == :"details-menu"

        params = {
          id: "#{@select_menu_id}-content",
          tag: @menu[:tag],
          role: role,
          classes: class_names(
            "SelectMenu",
            @menu[:classes],
            "SelectMenu--hasFilter" => filter.present?,
          ),
          data: @menu[:data],
          aria: {
            label: @menu[:label],
          }
        }
        params[:src] = @menu[:src] if @menu[:src].present?
        params[:preload] = @menu[:preload] if @menu[:preload]
        params[:right] = 0 if @align_right
        params.merge!(@menu[:params]) if @menu[:params].present?

        Primer::BaseComponent.new(**params)
      end

      def modal_component
        params = {
          classes: class_names("SelectMenu-modal", @modal[:classes])
        }
        params.merge!(@modal[:params]) if @modal[:params].present?

        if tabbed?
          Primer::Alpha::TabContainer.new(**params)
        else
          params[:tag] = :div
          Primer::BaseComponent.new(**T.unsafe(**params))
        end
      end

      def tabbed?
        @will_have_tabs || lists.size > 1
      end
    end
  end
end
