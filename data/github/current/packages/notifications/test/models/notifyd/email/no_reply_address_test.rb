# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  module Email
    class NoReplyAddressTest < GitHub::TestCase

      test "builds string field from name and handle" do
        assert_equal NoReplyAddress.new(name: "name", handle: "handle").to_s, "name <handle@noreply.github.com>"
      end

      test "works with a repository object string field from name and handle" do
        repo = create(:repository)
        assert_equal NoReplyAddress.new(name: repo.name_with_owner, handle: repo.to_s).to_s, "#{repo.name_with_owner} <#{repo}@noreply.#{GitHub.urls.smtp_domain}>"
      end

    end
  end
end
