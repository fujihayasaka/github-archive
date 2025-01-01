# typed: true
# frozen_string_literal: true

module GitHub
  class Octoshift
    # Tests are stubbed so that calls to Octoshift hit this FakeServer instead.
    class FakeServer
      def self.call(env)
        # For now, just return an empty response. Eventually this could be fleshed
        # out to return sensible dummy data.
        [200, { "Content-Type" => "application/protobuf" }, [""]] # Empty response from octoshift
      end
    end
  end
end
