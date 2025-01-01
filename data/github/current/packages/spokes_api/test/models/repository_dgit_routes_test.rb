# typed: true
# frozen_string_literal: true

require "test_helper"
require "gitrpc/protocol/dgit_lint"

class RepositoryDGitRoutesTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  include ::GitRPC::Protocol::DGit::RouteLintTest
  def dgit_route
    @repo.dgit_all_routes.first
  end
end
