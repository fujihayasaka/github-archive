# typed: true
# frozen_string_literal: true
module Freno
  class FakeClient < Client
    def replication_delay(*args)
      0.0 # no replication-delay
    end

    def check(*args)
      operation_allowed
    end

    def check_read(*args)
      operation_allowed
    end

    private

    def operation_allowed
      @operation_allowed ||= Freno::Client::Result.new(200) # 200-ok to read or write
    end
  end
end
