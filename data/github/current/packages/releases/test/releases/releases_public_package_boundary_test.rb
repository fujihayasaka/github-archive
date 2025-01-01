# typed: true
# frozen_string_literal: true

module ReleasesPublicPackageBoundary
  include T::Sig
  extend self

  sig { params(repository_id: Integer).returns(Integer) }
  def published_release_count_for_repository(repository_id)
    Release.published.where(repository_id: repository_id).count
  end

  extend GitHub::DomainIsolation::PackageBoundary
end
