# typed: true
# frozen_string_literal: true

module Repository::LatestReleaseDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))

    has_one :repository_latest_release, dependent: :destroy
    has_one :saved_latest_release, through: :repository_latest_release, source: :release

    batch_method(:latest_release) do |repos, actor|
      GitHub::PrefillAssociations.prefill_associations(repos, [:saved_latest_release])
      repos.index_with do |repo|
        repo.fetch_latest_release(actor)
      end
    end
  end

  def set_latest_release(release)
    return unless release.present?
    # Call .destroy on this model after creating it to avoid auto saving a duplicate when #save is called on the release.
    # We are running model validation manually in this way because .upsert does not do any validation.
    return unless RepositoryLatestRelease.new(repository: self, release: release).destroy.valid?

    RepositoryLatestRelease.upsert({ repository_id: self.id, release_id: release.id })
  end

  def fetch_latest_release(user)
    if repository_latest_release && repository_latest_release&.valid?
      T.must(repository_latest_release).release
    else
      # Fallback to querying elasticsearch if we don't have a valid latest release stored
      GitHub.dogstats.increment(
        "latest_release.fallback",
        { tags: ["reason:#{repository_latest_release.nil? ? "latest_release_nil" : "latest_release_invalid"}"] }
        )
      Release.query_releases(self, user, { filter_phrase: "draft:false prerelease:false", page: 1, limit: 1 }).models.first
    end
  end
end
