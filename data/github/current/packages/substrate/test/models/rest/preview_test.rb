# typed: true
# frozen_string_literal: true

require "test_helper"

class RESTPreviewTest < GitHub::TestCase
  def default_preview_data
    {
      name: :something,
      code_name: :superman,
      description: "Some API",
      owning_teams: ["@github/some-team"],
      start_year: 2013,
      start_month: 1,
    }
  end

  def test_parameters_are_checked
    # No error.
    preview = Rest::Preview.new(**default_preview_data)

    # A required parameter.
    data = default_preview_data.delete(:code_name)
    assert_raises ArgumentError do
      preview = Rest::Preview.new(data)
    end

    # An unknown parameter.
    assert_raises ArgumentError do
      preview = Rest::Preview.new(**default_preview_data.merge(no_such_param: "nope"))
    end
  end

  def test_media_version
    preview = Rest::Preview.new(**default_preview_data.merge(code_name: "hello-world"))
    assert_equal "hello-world-preview", preview.media_version
  end

  def test_available
    preview = Rest::Preview.new(**default_preview_data.merge(start_month: 4, start_year: 2018))
    assert preview.available?
  end

  def test_unavailable
    data = default_preview_data.merge(start_month: Rest::Preview::UNAVAILABLE, start_year: Rest::Preview::UNAVAILABLE)
    preview = Rest::Preview.new(**data)
    refute preview.available?
  end
end
