# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class PageBuildStatus < Platform::Enums::Base
      description "The possible page build states."
      visibility :internal

      [
        ::Page::Build::STATUS_BUILDING,
        ::Page::Build::STATUS_BUILT,
        ::Page::Build::STATUS_ERRORED,
      ].each do |state|
        value state.upcase, "The Page is #{state}.", value: state
      end
    end
  end
end
