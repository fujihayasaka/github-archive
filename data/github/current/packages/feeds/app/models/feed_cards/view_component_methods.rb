# typed: strict
# frozen_string_literal: true

module FeedCards
  module ViewComponentMethods
    extend T::Helpers
    requires_ancestor { ApplicationComponent }
    abstract!

    sig do
      overridable.params(
        item: T.untyped,
        viewer: T.nilable(User),
        feed: T.untyped,
        show_star_repo_buttons: T::Boolean,
        stats_timer_method: T.untyped,
        stats: T.untyped
      ).void
    end
    def initialize(
      item:,
      viewer: nil,
      feed: nil,
      show_star_repo_buttons: false,
      stats_timer_method: nil,
      stats: nil
    )
      @item = item
      @viewer = viewer
      @feed = feed
      @show_star_repo_buttons = show_star_repo_buttons
      @stats_timer_method = stats_timer_method
      @stats = stats
      @idx = T.let(nil, T.nilable(Integer))
    end

    sig { overridable.returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
    def heading_icon
      nil
    end

    private

    sig { returns(T.nilable(Integer)) }
    attr_reader :idx

    sig { params(idx: T.nilable(Integer)).void }
    attr_writer :idx

    sig { returns(T.untyped) }
    attr_reader :item

    sig { returns(T.untyped) }
    attr_reader :feed

    sig { returns(T.nilable(User)) }
    attr_reader :viewer

    sig { returns(T::Boolean) }
    attr_reader :show_star_repo_buttons

    sig { returns(T.untyped) }
    attr_reader :stats

    delegate(
      :action_string,
      :actor,
      :analytics_attributes,
      :announcement?,
      :contains_viewer?,
      :display_subject,
      :feed_post,
      :repository,
      :subject,
      :subject_id,
      :user_list,
      to: :item,
    )

    alias_method :action, :action_string

    sig { params(block: T.proc.void).returns(String) }
    def stats_timer(&block)
      if @stats_timer_method
        @stats_timer_method.call(stats, tags: ["item_key:#{item.item_key}"]) { yield }
      else
        yield
      end
    end
  end
end
