# typed: true
# frozen_string_literal: true

module Api::Serializer::ImmutableReleasesDependency
  extend T::Helpers

  requires_ancestor { T.class_of(Api::Serializer) }

  def immutable_releases_organization_settings_hash(data, options = {})
    {
      enforced_repositories: data[:enforced_repositories],
      selected_repositories_url: data[:selected_repositories_url]
    }.compact
  end

  def immutable_releases_organization_enforced_repositories_hash(data, options = {})
    {
      total_count: data[:total_count],
      repositories: data[:repositories].map { |repo| repository_hash(repo, options) }
    }
  end
end
