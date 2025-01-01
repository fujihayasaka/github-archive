# typed: true
# frozen_string_literal: true

require "test_helper"

class RESTPreviewsTest < Test::Fast::TestCase
  def test_a_fake_preview
    data = {
      name: :the_fake_preview,
      code_name: "superman",
      description: "Fake API",
      owning_teams: ["@github/some-team"],
      start_year: 2015,
      start_month: 8,
    }
    Rest::Previews.register data
    assert_equal "superman", Rest::Previews.get(:the_fake_preview).code_name
  ensure
    Rest::Previews::DEFAULT.delete(:the_fake_preview)
  end
end
