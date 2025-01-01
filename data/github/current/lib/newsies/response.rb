# typed: true
# frozen_string_literal: true

module Newsies
  class Response < Resiliency::Response
    attr_accessor :success
  end
end
