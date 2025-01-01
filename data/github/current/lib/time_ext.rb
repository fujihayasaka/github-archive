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

if Time.now.respond_to?(:to_proto)
  raise LoadError, "Time#to_proto should not exist"
else
  class Time
    sig do
      returns(Google::Protobuf::Timestamp)
    end
    def to_proto
      Google::Protobuf::Timestamp.new(seconds: to_i, nanos: nsec)
    end
  end
end
