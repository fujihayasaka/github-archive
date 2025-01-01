# frozen_string_literal: true

require "sorbet-runtime"
require "vexi"
require "feature_management_feature_flags"
require "minitest/autorun"
require "mocha/minitest"
require "debug"

require "testing/mock_factory"

module Minitest::Assertions
  def assert_same_elements(expected, current, msg = nil)
    assert expected_h = expected.each_with_object({}) { |e, h| h[e] ||= expected.count { |i| i == e } }
    assert current_h = current.each_with_object({}) { |e, h| h[e] ||= current.count { |i| i == e } }

    assert_equal(expected_h, current_h, msg)
  end
end

# rubocop:enable Style/ClassAndModuleChildren, Metrics/AbcSize
