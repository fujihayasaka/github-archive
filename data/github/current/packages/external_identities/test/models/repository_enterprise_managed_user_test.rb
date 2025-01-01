# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryEnterpriseManagedUserTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @emu = create(:emu)
    @biz = @emu.enterprise_managed_business
    @org = create :enterprise_linked_organization, business: @biz, admin: @emu
  end

  context "changing user repo visibility" do
    test "works when changing to private" do
      repo = create(:repository, owner: @emu)
      assert repo.set_permission(:private)
      assert_equal repo.visibility, Repository::PRIVATE_VISIBILITY
    end

    test "raises when changing to public" do
      repo = create(:private_repository, owner: @emu)
      assert_raises ArgumentError do
        repo.set_permission(:public)
      end
      assert_equal repo.visibility, Repository::PRIVATE_VISIBILITY
    end
  end

  context "changing org repo visibility" do
    test "works when changing to private" do
      repo = create(:repository, owner: @org)
      assert repo.set_permission(:private)
      assert_equal repo.visibility, Repository::PRIVATE_VISIBILITY
    end

    test "works when changing to internal" do
      repo = create(:repository, owner: @org)
      assert repo.set_permission(:internal)
      assert_equal repo.visibility, Repository::INTERNAL_VISIBILITY
    end

    test "raises when changing private to public" do
      repo = create(:private_repository, owner: @org)
      assert_raises ArgumentError do
        repo.set_permission(:public)
      end
      assert_equal repo.visibility, Repository::PRIVATE_VISIBILITY
    end

    test "raises when changing internal to public" do
      repo = create(:internal_repository, owner: @org)
      assert_raises ArgumentError do
        repo.set_permission(:public)
      end
      assert_equal repo.visibility, Repository::INTERNAL_VISIBILITY
    end
  end
end
