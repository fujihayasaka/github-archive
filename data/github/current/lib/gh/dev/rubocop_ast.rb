# typed: true
# frozen_string_literal: true

module GH
  module Dev
    class RuboCopAst
      major = T.let(nil, T.nilable(String))
      minor = T.let(nil, T.nilable(String))
      /^(?<major>\d+)\.(?<minor>\d+)\./ =~ RUBY_VERSION

      RUBY_VERSION_F = RUBY_VERSION.to_f

      # During the RUBY_NEXT builds, we can run into situations where Rubocop doesn't yet support the
      # latest minor version. To get around this, we temporarily downgrade the Ruby version used to the previous
      # stable minor version. This does not affect production code.
      # Reference: https://github.com/github/ruby-architecture/issues/679
      RUBY_FALLBACK_VERSION = if RUBY_DESCRIPTION.match? /dev/
        if minor.to_i != 0
          minor = (minor.to_i - 1).to_s
          "#{major}.#{minor}".to_f
        elsif major == "4"
          3.4
        else
          # It's not possible to predict what will be the last supported ruby 4.X
          # minor version before ruby gets the next major upgrade to 5.0.
          # If you hit this error feel free to add a new case that hardcodes the
          # most recent minor 4.x version as a fallback for 5.0.
        end
      end

      def self.processed_source(source, path = nil)
        RuboCop::ProcessedSource.new(source, RUBY_VERSION_F, path)
      rescue ArgumentError => e
        raise e unless RUBY_FALLBACK_VERSION && e.message.match?(/RuboCop/)
        RuboCop::ProcessedSource.new(source, RUBY_FALLBACK_VERSION, path)
      end
    end
  end
end
