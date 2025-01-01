# typed: false
# frozen_string_literal: true

module Gist::SpokesAPI
  include SpokesAPI::ContextDependency

  def spokes_api(timeout: nil)
    if timeout
      return SpokesAPI::Client.for_gist(
        id,
        gist_name: repo_name,
        timeout: timeout,
        context: self.spokes_api_context
      )
    end
    @spokes_api ||= SpokesAPI::Client.for_gist(id, gist_name: repo_name, context: self.spokes_api_context)
  end
end
