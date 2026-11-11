# typed: true
# frozen_string_literal:true

module Munger
  class Client

    # snapshot_date: A String representing the last time the suggestions were generated
    #
    # user_id: An Integer representing the database ID for a User
    #
    # repository_id: An Integer representing the database ID for a Repository
    #
    # algorithm_version: A String representing the version of the ML algorithm the suggestions were generated from
    #
    # score: A Float (between 0.0 and 1.0) representing the strength of the suggestion from the ML algorithm
    #
    class DataUnsubscribeSuggestion
      attr_reader :snapshot_date, :user_id, :repository_id, :algorithm_version, :score
      attr_accessor :repository

      def initialize(snapshot_date:, user_id:, repository_id:, algorithm_version:, score: 0)
        @snapshot_date = snapshot_date
        @user_id = user_id
        @repository_id = repository_id
        @algorithm_version = algorithm_version
        @score = score
      end
    end
  end
end
