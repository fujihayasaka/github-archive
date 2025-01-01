# typed: strict
# frozen_string_literal: true

require "github/orca"

module Orca

  include GitHub::Memoizer

  SERVICE_NAME = T.let("orca", String)

  sig { returns(Client) }
  def self.client
    @client ||= T.let(Client.new(
      base_url: GitHub.orca_base_url,
      hmac_key: GitHub.orca_hmac_key
    ), T.nilable(Client))
  end
end
