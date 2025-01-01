# typed: strict
# frozen_string_literal: true

module Repositories
  class Domain
    class Topics < GH::Domain::Base
      # Public: Fetch topics by name.
      #
      # Options:
      # - names - The topic names.
      #
      # Returns an array of Topics
      sig { params(names: T::Array[String]).returns(GH::Domain::Collection[Topic]).checked(:always).on_failure(:raise) }
      def by_names(names:)
        results = ::Topic.where(name: names).to_a
        GH::Domain::Collection.new(results)
      end
    end
  end
end
