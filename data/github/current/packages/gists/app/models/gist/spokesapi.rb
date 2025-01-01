# typed: false
# frozen_string_literal: true

module Gist::SpokesAPI
  def spokes_api
    @spokes_api ||= SpokesAPI::Client.for_gist(id, gist_name: repo_name)
  end
end
