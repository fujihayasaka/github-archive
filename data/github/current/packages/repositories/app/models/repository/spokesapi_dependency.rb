# typed: true
# frozen_string_literal: true

module Repository::SpokesAPIDependency
  include SpokesAPI::ContextDependency

  extend T::Helpers

  requires_ancestor { Repository }

  # Public: A Spokes API client for this repository.
  sig { params(timeout: T.nilable(T.any(Integer, Float))).returns(SpokesAPI::Client) }
  def spokes_api(timeout: nil)
    if timeout
      return SpokesAPI::Client.for_repository(
        repository.id,
        network_id: repository.network_id,
        timeout: timeout,
        context: self.spokes_api_context
      )
    end
    @spokes_api ||= SpokesAPI::Client.for_repository(id, network_id: network_id, context: self.spokes_api_context)
  end

  # Public: A facade Spokes API client for this repository.
  def spokes_api_facade
    @spokes_api_facade ||= Repository::SpokesClientFacade.new(self)
  end
end
