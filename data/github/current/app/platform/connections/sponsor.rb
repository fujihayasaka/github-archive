# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Sponsor < Connections::Base
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      description "A list of users and organizations sponsoring someone via GitHub Sponsors."

      total_count_field
    end
  end
end
