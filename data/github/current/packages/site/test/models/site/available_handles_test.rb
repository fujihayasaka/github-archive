# typed: true
# frozen_string_literal: true

require "test_helper"

class SiteAvailableHandlesTest < GitHub::TestCase
  context "load_json" do
    test "loads a json file" do
      refute Site::AvailableHandles::load_json("test/fixtures/site/approved_handles.json").empty?
    end

    test "return an empty hash if json file doesn't exist" do
      assert Site::AvailableHandles::load_json("test/fixtures/site/i-dont-exist.json").empty?
    end
  end
end
