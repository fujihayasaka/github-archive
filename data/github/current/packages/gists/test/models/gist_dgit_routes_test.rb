# typed: true
# frozen_string_literal: true

require "test_helper"
require "gitrpc/protocol/dgit_lint"

class GistDGitRoutesTest < GitHub::TestCase
  fixtures do
    @gist = GistHelpers.generate contents: [{ name: "first.md", value: "# First!\n" }]
  end

  include ::GitRPC::Protocol::DGit::RouteLintTest
  def dgit_route
    @gist.dgit_read_routes.first
  end
end
