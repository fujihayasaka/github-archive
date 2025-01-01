# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class RateLimitTest < Api::SerializerTestCase
  class RequestContextMock
    def initialize(user)
      @user = user
    end

    def current_user
      @user
    end

    def medias
      Api::AcceptedMediaTypes.new([], "/")
    end

    def method_missing(message, *args, &block)
      nil
    end
  end

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    user = create :user
    request_context = RequestContextMock.new(user)
    @statuses = Api::RateLimitStatus.all(request_context)
  end

  context "#rate_limit_statuses_hash" do
    test "payload is valid" do
      output = rate_limit_statuses(@statuses)
      assert_same_elements %w[resources rate], output.keys
    end

    # TODO: Use assert_openapi to assert rate property isn't returned
    #       for the appropriate API versions.
    unless GitHub.enterprise?
      test "can omit rate property" do
        with_changeset "remove_rate_limit_rate" do
          output = rate_limit_statuses(@statuses)
          assert output.key?("resources")
          assert !output.key?("rate")
        end
      end
    end

    # TODO: Use assert_openapi to assert rate property is returned
    #       for the appropriate API versions.
    test "can include rate property" do
      output = rate_limit_statuses(@statuses)
      assert output.key?("resources")
      assert output.key?("rate")
    end
  end
end
