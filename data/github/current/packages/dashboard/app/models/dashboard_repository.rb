# typed: strict
# frozen_string_literal: true

# A repository displayed on the dashboard.
class DashboardRepository
  sig { params(repository: Repository).void }
  def initialize(repository)
    @repository = repository
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def to_h
    {
      globalRelayId: repository.global_relay_id,
      name: repository.name,
      description: repository.description,
      owner: {
        displayLogin: T.must(repository.owner).display_login,
        isOrganization: T.must(repository.owner).organization?,
      },
      isFork: repository.fork?,
      isPrivate: repository.private?,
      isTemplate: repository.template?,
    }
  end

  private

  sig { returns(Repository) }
  attr_reader :repository
end
