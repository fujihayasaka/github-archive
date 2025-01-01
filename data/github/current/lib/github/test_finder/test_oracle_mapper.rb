# typed: true
# frozen_string_literal: true

require "github/test_finder/test_oracle"
require "ruby-progressbar"
require "shellwords"
require "thor"

module GitHub
  module TestFinder
    class GitHubAPIException < StandardError; end

    class TestOracleMapper
      include Thor::Shell
      extend T::Sig

      attr_reader :test_oracle

      sig { params(path: Pathname, sharded_dbs_path: Pathname).void }
      def initialize(path, sharded_dbs_path)
        @test_oracle = GitHub::TestFinder::TestOracle.new(path.to_s, sharded_dbs_path.to_s)
      end

      sig { params(path: String).returns(T::Array[String]) }
      def test_paths_for(path)
        @test_oracle.query([path])
      end

      sig { params(paths: T::Array[String]).returns(T::Hash[String, Integer]) }
      def impact_for(paths)
        say "Calculating impact (affected test files) for #{paths.count} changed files.", :blue
        db_paths = paths.reject do |path|
          path.end_with?("_test.rb")
        end
        test_paths = paths - db_paths

        impact = @test_oracle.query_impact(db_paths)
        impact.merge(test_paths.map { |path| [path, 1] }.to_h)
      end

      sig { returns(Integer) }
      def record_count
        @test_oracle.record_count
      end
    end
  end
end
