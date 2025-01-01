# typed: true
# frozen_string_literal: true

module Newsies
  # Tracks the delivery of a Thread notification to multiple Users across
  # multiple Handlers.
  class Delivery
    # summary  - A Summary object for the Thread.
    # comment  - The Comment object that is initiating the notification.
    def initialize(summary, comment)
      @summary = summary
      @comment = comment
    end

    # Public: Returns the Summary of the thread that notifications are being
    # delivered for.
    attr_reader :summary

    # Public: Returns the Comment that notifications are being delivered for.
    attr_reader :comment

    # References the List of the Thread that is triggering the
    # notification.
    #
    # Returns a List object.
    def list
      @summary.list
    end

    # References the Thread that is triggering the notification.
    #
    # Returns a Thread object.
    def thread
      @summary.thread
    end

    def list_id
      Newsies::List.to_id(list)
    end

    def list_type
      Newsies::List.to_type(list)
    end

    def thread_id
      Newsies::Thread.to_id(thread)
    end

    def thread_type
      Newsies::Thread.to_type(thread)
    end

    def comment_id
      Newsies::Comment.to_id(comment)
    end

    def comment_type
      Newsies::Comment.to_type(comment)
    end
  end
end
