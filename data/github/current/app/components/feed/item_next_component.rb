# typed: false
# frozen_string_literal: true

module Feed
  class ItemNextComponent < ApplicationComponent
    renders_one :heading
    renders_one :subheading
    renders_one :heading_action
    renders_one :heading_subject
    renders_one :border
    renders_one :heading_menu
    renders_one :action_button
    renders_one :comments

    renders_one :body, ItemBodyComponent

    renders_one :footer, -> (**system_arguments, &block) do
      content = block.call
      return if content.blank?
      render Primer::BaseComponent.new(
        tag: :footer,
        color: :muted,
        mx: 0,
        mt: 3,
        mb: 0,
        flex: 1,
        test_selector: "feed-item-footer",
        **system_arguments
      ).with_content(content)
    end

    renders_one :related_items_preview, -> (**system_arguments, &block) do
      content = block.call
      return if content.blank?

      render Primer::BaseComponent.new(
        tag: :div,
        test_selector: "feed-rollup-preview-related-items",
        **system_arguments
      ).with_content(content)
    end

    renders_one :related_items, -> (**_system_arguments, &block) do
      content = block.call
      return if content.blank?

      render Primer::BaseComponent.new(
        tag: :div,
        test_selector: "feed-rollup-related-items",
      ) do
        render Feed::RollupContainerComponent.new(item:) do
          render Primer::Box.new(
            bg: :overlay,
            classes: "Details-content--hidden",
            data: helpers.feed_clicks_hydro_attrs(click_target: "rollup_hidden_card_bottom", feed_item: item)
          ).with_content(content)
        end
      end
    end

    attr_reader :actor, :action, :timestamp, :repository, :item
    delegate :related_item?, :announcement?, :discussion_event?, :recommendation_event?, :release_event?, :trending_repository_event?, to: :item

    def initialize(actor:, action:, timestamp:, item:, repository: nil, heading_icon: nil)
      @actor = actor
      @action = action
      @item = item
      @repository = repository

      @timestamp = timestamp
      # some events in prod might have a 1970-01-01 timestamp
      # if we forgot to add a `created_at` field so we should omit these rather than show something happened "53y" ago
      @timestamp = nil if timestamp && Date.today.year - Date.parse(timestamp.to_s).year > 3
      @heading_icon = heading_icon
    end

    private

    def heading_icon
      return if item.announcement?

      @heading_icon ||= begin
        component_class = Conduit::Web::Renderer.new(item:).component
        component_class::HEADING_ICON if component_class.const_defined?(:HEADING_ICON)
      end
    end

    def linked_avatar(user, size: 32, data: {})
      helpers.feed_user_avatar(user, item, size: size, data: data)
    end

    def linked_login(user, data: {}, **sys_args)
      helpers.link_to_feed_user(user, item, data: data, **sys_args)
    end

    def linked_repo(repo, data = {})
      helpers.link_to_feed_repo(repo, item, data: data)
    end

    def feed_view_hydro_attrs
      helpers.feed_view_hydro_attrs(feed_item: item)
    end

    def render_as_rollup?
      item.rollup? && item.show_related_items?
    end

    def skip_header?
      related_item?
    end

    def show_label?
      item.list_context? && !item.label.nil?
    end

    def preview_related_item
      item.related_items[0]
    end

    def more_related_items
      item.related_items.slice(0)
    end
  end
end
