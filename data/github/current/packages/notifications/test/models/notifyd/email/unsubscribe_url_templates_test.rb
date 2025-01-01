# typed: true
# frozen_string_literal: true

require "test_helper"


module Notifyd::Email
  class UnsubscribeUrlTemplatesTest < GitHub::TestCase
    test "#serialize" do
      templates = UnsubscribeUrlTemplates.new.serialize

      assert_equal "https://github.com/notifications/unsubscribe-auth/{token}", templates.footer
      assert_equal "https://github.com/notifications/unsubscribe/one-click/{token}", templates.header
    end
  end
end
