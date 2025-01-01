# typed: true
# frozen_string_literal: true

class PinnedFeed < ApplicationRecord::Domain::Users
  belongs_to :user, inverse_of: :pinned_feeds
  belongs_to :topic

  delegate :name, to: :topic
  alias :display_name :name
end
