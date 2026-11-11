# typed: true
# frozen_string_literal: true

class FeedFilterSettings < ApplicationRecord::Domain::UsersBallast

  belongs_to :user, required: true, inverse_of: :feed_filter_settings

  validates :user_id, presence: true

  attribute :user_id, :integer
  attribute :is_topic, :boolean, default: false
  attribute :announcements_enabled, :boolean, default: true
  attribute :releases_enabled, :boolean, default: true
  attribute :sponsors_enabled, :boolean, default: true
  attribute :stars_enabled, :boolean, default: true
  attribute :repositories_enabled, :boolean, default: true
  attribute :repository_activity_enabled, :boolean, default: true
  attribute :follows_enabled, :boolean, default: true
  attribute :recommendations_enabled, :boolean, default: true
  attribute :posts_enabled, :boolean, default: true
  attribute :explicit_only_enabled, :boolean, default: true

  def values
    {
      "Announcements" => announcements_enabled,
      "Releases" => releases_enabled,
      "Sponsors" => sponsors_enabled,
      "Stars" => stars_enabled,
      "Repositories" => repositories_enabled,
      "Follows" => follows_enabled,
      "Recommendations" => recommendations_enabled,
      "RepositoryActivity" => repository_activity_enabled,
    }
  end

end
