# typed: true
# frozen_string_literal: true
module Platform
  module Evolution
    # `Platform::Evolution::UpcomingChange` is a wrapper around `Platform::Evolution::Change`
    # representing a single change in a schema. For a single `Change`
    # there might be multiple `UpcomingChange` objects if the member is reused
    # under different parents.
    #
    # The `UpcomingChange` objects wraps the `Change` but also provides a
    # `path` attribute, the actual location of this specific change for example
    # ``[MyType, MyField]` would be the path to `myChangingArgument`
    class UpcomingChange
      attr_reader :path, :change

      delegate :apply_on, :description, :reason, :criticality, :owner, to: :change

      def initialize(change, path:)
        @change = change
        @path = path
      end

      def location
        (path + [change.target]).map(&:graphql_name).join(".")
      end

      def to_h
        {
          location: location,
          description: description,
          reason: reason,
          date: apply_on.to_s,
          criticality: criticality.to_s,
          owner: owner,
        }
      end
    end
  end
end
