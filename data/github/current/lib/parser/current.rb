# typed: true
# frozen_string_literal: true

#
# This file exists so we bypass the check that parser does
# on version mismatches, also for small version bumps in Ruby.
#
# Since upstream takes time to update to the latest patches, and we don't care
# about minor syntax differences, we want to avoid the warning.
#
# Also see https://github.com/github/github/pull/75460
major = minor = T.let(nil, T.nilable(String))
/^(?<major>\d+)\.(?<minor>\d+)\./ =~ RUBY_VERSION

required = false

begin
  required = require "parser/ruby#{major}#{minor}"
rescue LoadError
  if RUBY_DESCRIPTION.match? /dev/
    if minor.to_i != 0
      minor = (minor.to_i - 1).to_s
    else
      raise NotImplementedError
      # It's not possible to predict what will be the last supported ruby 3.X minor version
      # before ruby gets the next major upgrade to 4.X
      # if you hit this error feel free to delete the `raise`,
      # hardcode the most recent minor 3.X version and uncomment the lines below:
      # major = (major.to_i - 1).to_s
      # minor = "?"
    end
  end
end

require "parser/ruby#{major}#{minor}" unless required
Parser::CurrentRuby = Parser.const_get("Ruby#{major}#{minor}")
