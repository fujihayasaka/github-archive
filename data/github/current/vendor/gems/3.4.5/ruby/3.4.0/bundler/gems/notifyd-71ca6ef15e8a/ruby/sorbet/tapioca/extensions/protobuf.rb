# typed: true
# frozen_string_literal: true

# Workaround for https://github.com/Shopify/tapioca/issues/442
# The issue here is that tapoca basically assumes a that it is working with a
# rails app, which isn't the case. Because of that tapioca doesn't load some of
# the dependencies and that causes the DSL generators to not work.
#
# The protobuf DSL compiler has a check where, in case this isn't required it
# doesn't even load. By requiring it here, we force tapioca to work.
require "google/protobuf"
