# typed: true
# frozen_string_literal: true

class OrganizationFeedFilterSettings < ApplicationRecord::Domain::UsersBallast

  belongs_to :user, required: true, inverse_of: :organization_feed_filter_settings

  validates :user_id, presence: true

  attribute :user_id, :integer
  attribute :releases_enabled, :boolean, default: true
  attribute :repositories_enabled, :boolean, default: true
  attribute :repository_activity_enabled, :boolean, default: true

  def values
    {
      "Releases" => releases_enabled,
      "Repositories" => repositories_enabled,
      "RepositoryActivity" => repository_activity_enabled,
    }
  end

end
