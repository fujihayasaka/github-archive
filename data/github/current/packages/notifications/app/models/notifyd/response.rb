# typed: true
# frozen_string_literal: true

module Notifyd
  class Response < Resiliency::Response
    attr_accessor :success
  end
end
