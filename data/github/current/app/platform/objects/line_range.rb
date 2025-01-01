# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class LineRange
      attr_accessor :lines
      attr_reader :commit
      attr_reader :repository

      def initialize(commit, lines, repository)
        @commit = commit
        @lines = []
        @now = Time.now
        @repository = repository

        domain = [0, @now - commit.repository.created_at]
        range = (1..10).map { |ix| "#{ix}" }
        @quantile = Quantile.new(domain: domain, range: range)
      end

      def scale
        @quantile.scale(@now - @commit.authored_date)
      end

      def platform_type_name
        # This class is actually a PORO defined in objects/blame.rb
        "BlameRange"
      end
    end
  end
end
