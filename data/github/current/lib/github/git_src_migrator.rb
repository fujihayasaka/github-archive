# typed: true
# frozen_string_literal: true

module GitHub
  class GitSrcMigrator
    class FakeServer
      def self.call(env)
        [200, { "Content-Type" => "application/protobuf" }, [""]]
      end
    end
  end
end
