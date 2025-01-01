# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationAllowPrivateRepositoryForkingTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @owner = @org.admins.first
    @repo = create :private_repository, :minimal, owner: @org
  end

  test "disabling then re-enabling allow repo configuration" do
    @org.block_private_repository_forking(actor: @owner)
    @org.allow_private_repository_forking(actor: @owner)

    assert_predicate @repo, :allow_private_repository_forking?

    @repo.block_private_repository_forking(actor: @owner)

    refute_predicate @repo, :allow_private_repository_forking?
  end
end
