# typed: true
# frozen_string_literal:true

module Munger
  class Client

    # name: A String of the topic's name.
    #
    # search_score: A Float value representing the Repository => DataTopic score. It is used to
    # rank how well a repository applies to a topic in relation to all other repositories.
    #
    # suggestion_score: A Float value representing the DataTopic => Repository score. Used to rank
    # the suggested topics for a repository.
    #
    class DataTopic
      attr_reader :name, :search_score, :suggestion_score

      def initialize(name:, search_score: 0, suggestion_score: 0)
        @name = name
        @search_score = search_score
        @suggestion_score = suggestion_score
      end
    end
  end
end
