# typed: true
# frozen_string_literal: true

module KvMigration
  module Generator
    class GenerateGhesMigration
      def self.call(version)
        system("bin/generate-transition-migration", version)

        KvMigration::Generator::RunMigration.call
      end
    end
  end
end
