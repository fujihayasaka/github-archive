# typed: strict
# frozen_string_literal: true

module Feed
  class HeadingMenuComponent < ApplicationComponent
    sig do
      params(
        item: Conduit::FeedItem,
        actor: T.nilable(User),
        system_arguments: T.anything,
      ).void
    end
    def initialize(item:, actor: nil, **system_arguments)
      @item = item
      @actor = actor
      @system_arguments = system_arguments
    end

    sig { returns(T::Boolean) }
    def render?
      logged_in?
    end

    sig { returns(Conduit::FeedItem) }
    attr_reader :item

    sig { returns(T::Hash[Symbol, T.anything]) }
    attr_reader :system_arguments

    delegate :reason, :reason_message, :actor_reason?, to: :item

    sig { returns(T.nilable(User)) }
    memoize def actor
      @actor || item.actor
    end

    private

    sig { returns(T::Boolean) }
    memoize def show_reason?
      reason.present? && reason_message.present?
    end

    sig { returns(T::Boolean) }
    memoize def show_disinterest_option?
      !viewer_is_actor && !item.feed&.org_context?
    end

    sig { returns(String) }
    def disinterest_dialog_id
      "feed-disinterest-dialog-#{item.event_id}"
    end

    sig { returns(T::Hash[Symbol, T.anything]) }
    def disinterest_dialog_item_data
      {
        show_dialog_id: disinterest_dialog_id,

        # Hydro click attributes
        actor_id: current_user.id,
        resource_id: item.subject&.id,
        resource_type: item.resource_type,
        event_id: item.event_id,
        event_type_string: item.event_type.to_s,
        clicked_at: Time.current.to_i,
        identifier: item.identifier,
        source: item.source,
        originating_url: request&.original_url,
      }
    end

    sig { returns(String) }
    def report_user_dialog_id
      "feed-user-block-dialog-#{item.event_id}"
    end

    sig { returns(T::Boolean) }
    memoize def show_unfollowable_actor_option?
      return false unless actor.present?

      !!actor_reason? && reason.split(",").include?("followed")
    end

    sig { returns(T::Boolean) }
    memoize def show_unstarrable_option?
      return false unless actor.present?

      !!reason_message&.include?("starred") && !item.announcement? && item.repository.present?
    end

    sig { returns(String) }
    def hide_label
      item.user_hidden? ? "Unhide event" : "Hide event"
    end

    sig { returns(Symbol) }
    def hide_method
      item.user_hidden? ? :delete : :post
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    def hide_inputs
      [
        { name: "event_id", value: item.event_id },
        { name: "event_hmac", value: Conduit.hmac_for_event_id(item.event_id) },
      ]
    end

    sig { returns(T::Boolean) }
    memoize def show_dismiss_announcement_option?
      item.announcement?
    end

    sig { returns(T::Array[T::Hash[Symbol, String]]) }
    memoize def dismiss_announcement_inputs
      [
        { name: "event_id", value: item.event_id },
        { name: "resource_id", value: item.resource_id },
        { name: "resource_type", value: item.resource_type },
        { name: "card_type", value: item.event_type },
        { name: "undo", value: "false" },
        { name: "identifier", value: item.identifier },
        { name: "reason_dismissed", value: "dismissed" },
      ]
    end

    sig { returns(T::Boolean) }
    def viewer_belongs_to_org?
      return false if !actor_is_org?

      T.cast(actor, Organization).direct_or_team_member?(current_user)
    end

    sig { returns(T.nilable(Integer)) }
    def actor_id
      item.actor_id
    end

    sig { returns(T::Boolean) }
    def actor_is_org?
      actor.is_a?(Organization)
    end

    sig { returns(T.nilable(String)) }
    def org_report_path
      return nil unless actor_is_org?
      flavored_contact_path(report: actor.to_s, flavor: "report-abuse")
    end

    sig { returns(T::Boolean) }
    def viewer_is_actor
      current_user.id == actor_id
    end
  end
end
