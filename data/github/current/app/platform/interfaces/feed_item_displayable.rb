# typed: true
# frozen_string_literal: true
#
module Platform
  module Interfaces
    module FeedItemDisplayable
      include Platform::Interfaces::Base
      description "An item that is displayable in the dashboard feed"
      mobile_only :true

      created_at_field

      field :description, String, "A single sentence description of this event.", null: false

      field :related_items, [Unions::FeedItem], "Related items to this item.", null: false

      field :related_by, Enums::FeedItemRelatedBy, "The relationship between this item and the related items.", null: true

      field :reason_message, String, "The reason why this item is being displayed.", null: true

      field :subject_is_viewer, Boolean, "Whether or not the subject of this item is the viewer", null: false

      field :dismissable, Boolean, "Whether or not this item is dismissable", null: false, method: :dismissible?

      field :identifier, String, "A unique identifier for this item", null: false
    end
  end
end
