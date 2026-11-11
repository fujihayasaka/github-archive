# typed: strict
# frozen_string_literal: true

module RetroactiveImmutability
  class Eligibility
    sig { params(repo: ::Repository, cursor: Integer, batch_size: Integer).returns(ActiveRecord::Relation) }
    def self.eligible_releases(repo, cursor:, batch_size:)
      ::Release
        .where(repository_id: repo.id, immutable: false)
        .published
        .where("id < ?", cursor)
        .order(id: :desc)
        .limit(batch_size)
    end
  end
end
