# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class Sponsor < Edges::Base
      visibility :public, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      description "Represents a user or organization who is sponsoring someone in GitHub Sponsors."

      # TODO: We might have to adjust this based on public/anonymous sponsorships
      def self.authorized?(object, context)
        sponsor = object.node
        Objects::User.authorized?(sponsor, context)
      end

      node_type Unions::Sponsor
    end
  end
end
