# typed: strict
# frozen_string_literal: true

# A repository displayed on the dashboard.
class DashboardRepository
  include UrlHelper

  sig { params(repository: Repository).void }
  def initialize(repository)
    @repository = repository
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_h
    {
      id: repository.id,
      value: repository.name_with_display_owner,
      url: repository_path(repository),
      avatar_url: T.must(repository.owner).primary_avatar_url,
    }
  end

  private

  sig { returns(Repository) }
  attr_reader :repository
end
