# frozen_string_literal: true
# typed: true

module GitRPC
  class Client
    def grep(*patterns, dirs:, tree:)
      send_message(:grep, patterns, dirs: dirs, tree: tree)
    end
  end
end
