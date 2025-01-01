# typed: true
# frozen_string_literal: true

require "flipper"
require "flipper/groups"

# See lib/flipper/groups.rb for list of groups
Flipper::Groups.register_groups

# Disable the automatic load of the memoizer middleware. The few processes that currently uses the middelware will 'use' it on their own
Rails.application.configure do
  T.bind(self, Rails::Application)
  if ENV["RAILS_ENV"] != "test"  # config.flipper doesn't exist in the github-system CI builds
    config.flipper.memoize = false
  end
end

module Flipper
  # TODO: push this into Flipper itself
  class Type
    def to_s
      value.to_s
    end
  end
end

require "flipper/employee_mode"
require "flipper/vexi_proxy"
require "flipper/concurrency_mode"
