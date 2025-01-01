# typed: true
# frozen_string_literal: true

module Coders
  module Page
    class BuildCoder < Coders::Base
      data_accessors :pusher_id,
                     :commit,
                     :status,
                     :error,
                     :backtrace,
                     :duration
    end
  end
end
