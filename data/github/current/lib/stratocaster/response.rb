# typed: true
# frozen_string_literal: true

module Stratocaster
  class Response
    attr_reader :items, :error

    # Public: Given a response from the Stratocaster service, wrap it so we can get some helper
    # methods around the success of the response. We currently always want the response to be
    # an Array.
    #
    # blk - A block to call to build the response.
    #
    def initialize(&blk)
      @items = begin
        Array(blk.call)
      rescue RuntimeError, ActiveRecord::NoDatabaseError, Errno::ECONNREFUSED => error
        GitHub.dogstats.increment("stratocaster.unavailable")
        Failbot.report(error, app: "github-stratocaster")
        @error = error
        []
      end
    end

    # Public: If the initial call to get the resource has failed, we can assume that Stratocaster
    # is unavailable.
    #
    # Returns true or false.
    def unavailable?
      !!@error
    end
  end
end
