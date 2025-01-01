# typed: true
# frozen_string_literal:true

module Munger
  class Client

    # id: An Integer representing the database ID which identifies the navigation destination.
    # Might be nil if not available.
    #
    # name: A String that uniquely identifies the navigation destination,
    # e.g. 'github/ee-panda-rocket' for a team.
    #
    # type: A String defining the type of the navigation destination,
    # e.g. 'Team', 'Repository' or 'Project'.
    #
    # visit_count: An Integer indicating how often the navigation destination was visited.
    #
    # last_visited_at: An Integer representing the timestamp in seconds since unix epoch
    # when the navigation destination was visted last.
    #
    # generated_at: An Integer representing the timestamp in seconds since unix epoch
    # when the data for this navigation destination was calculated.
    #
    class DataNavigationDestination
      attr_reader :id, :name, :type, :visit_count, :last_visited_at, :generated_at

      def initialize(id:, name:, type:, visit_count:, last_visited_at:, generated_at:)
        @id = id
        @name = name
        @type = type
        @visit_count = visit_count
        @last_visited_at = Time.at(last_visited_at).to_datetime
        @generated_at = Time.at(generated_at).to_datetime
      end
    end
  end
end
