# typed: true
# frozen_string_literal: true

# You can also remove all the silencers if you're trying to debug
# a problem that might stem from framework code.
#Rails.backtrace_cleaner.remove_silencers!

# Update silencer configuration to prevent removing packages/ paths from backtraces.
# See https://github.com/github/github/issues/240017
Rails.backtrace_cleaner.remove_silencers!
# Substitute Rails::BacktraceCleaner silencer with one that respects packages/ app dirs.
# N.B. this regex is stricter than the existing ActiveSupport::BacktraceCleaner silencers,
# so they're omitted.
Rails.backtrace_cleaner.add_silencer { |line| !/\A(?:\.\/)?(?:app|config|lib|test|packages|\(\w*\))/.match?(line) }
