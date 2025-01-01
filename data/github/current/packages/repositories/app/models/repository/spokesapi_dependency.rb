# typed: false
# frozen_string_literal: true

module Repository::SpokesAPIDependency
  # Public: A Spokes API client for this repository.
  def spokes_api
    @spokes_api ||= SpokesAPI::Client.for_repository(id, network_id: network_id)
  end

  # Public: A facade Spokes API client for this repository.
  def spokes_api_facade
    @spokes_api_facade ||= Repository::SpokesClientFacade.new(self)
  end
end
