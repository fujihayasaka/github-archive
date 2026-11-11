# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    def describe(commitish, len = 40)
      send_message(:describe, commitish, len)
    end
  end
end
