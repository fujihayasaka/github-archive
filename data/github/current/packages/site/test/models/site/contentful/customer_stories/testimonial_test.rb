# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Contentful::CustomerStories::TestimonialTest < GitHub::TestCase
  setup do
    @testimonial = VCR.use_cassette("contentful/customer-stories-testimonial") do
      Site::Contentful::CustomerStories::Testimonial.find("Mona Cat")
    end
  end

  test "returns data from Contentful" do
    assert_equal "Mona Cat", @testimonial.name
    assert_equal "Mascot", @testimonial.position
    assert_equal "GitHub", @testimonial.company
  end

  test "profile photo is JSONified" do
    profile = @testimonial.to_json[:profile]

    assert_equal @testimonial.profile.url, profile[:url]
    assert_equal @testimonial.profile.description, profile[:description]
    assert_equal @testimonial.profile.title, profile[:title]
  end
end
