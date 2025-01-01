# typed: true
# frozen_string_literal: true

require "mochilo"

if Time.now.respond_to?(:to_bpack)
  raise LoadError, "Time#to_bpack should not exist"
else
  class Time
    def to_bpack
      Mochilo.pack(self.to_i)
    end
  end
end
