# typed: true
# frozen_string_literal: true

require "test_helper"

class TechStackNameTest < GitHub::TestCase
  setup do
    @typescript = TechStackName.lookup_by_name("TypeScript")
  end

  test "#to_s" do
    assert_equal "TypeScript", @typescript.to_s
  end
end
