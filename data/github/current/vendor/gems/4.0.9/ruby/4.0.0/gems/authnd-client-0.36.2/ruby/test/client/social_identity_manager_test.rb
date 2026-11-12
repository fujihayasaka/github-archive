# frozen_string_literal: true

require_relative "../test_helper"

module Authnd
  module Client
    class SocialIdentityManagerTest < Minitest::Test
      include ServiceClientTestHelpers

      def test_initialize_with_string
        ex = assert_raises ArgumentError do
          Authnd::Client::SocialIdentityManager.new("not_a_faraday_connection", catalog_service: TEST_CATALOG_SERVICE)
        end
        assert_equal "connection is not a Faraday::Connection", ex.message
      end

      def test_find_social_identity_requires_user_email_id_as_integer
        manager = Authnd::Client::SocialIdentityManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        ex = assert_raises ArgumentError do
          manager.find_social_identity(1, "1234", "not_an_integer")
        end
        assert_equal "user_email_id must be an integer", ex.message
      end

      def test_find_social_identity_requires_provider_as_integer
        manager = Authnd::Client::SocialIdentityManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        ex = assert_raises ArgumentError do
          manager.find_social_identity("not_an_integer", "1234", 1)
        end
        assert_equal "provider must be an integer (enum)", ex.message
      end

      def test_find_social_identity_requires_subject_id_as_string
        manager = Authnd::Client::SocialIdentityManager.new(test_connection, catalog_service: TEST_CATALOG_SERVICE)
        ex = assert_raises ArgumentError do
          manager.find_social_identity(1, 1234, 1)
        end
        assert_equal "subject_id must be a string", ex.message
      end
    end
  end
end
