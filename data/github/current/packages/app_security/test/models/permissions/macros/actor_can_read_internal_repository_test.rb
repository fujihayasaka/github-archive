# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::ActorCanReadInternalRepositoryTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @rando = create :user

    @org = create(:enterprise_linked_organization)
    @org2 = create(:organization, business: @org.business)

    @admin = @org.admins.first
    @member = create(:user)
    @billing_manager = create :user
    @org2.add_member(@member, action: :read)
    @org.business.billing.add_manager @billing_manager, actor: @admin

    @internal_repo = create(:internal_repository, :minimal, owner: @org)
  end

  test "Non-internal repos are not readable" do
    public_repo = create(:public_repository, :minimal)
    refute @rando.can_read_internal_repository?(public_repo)

    private_repo = create(:private_repository, :minimal)
    refute @rando.can_read_internal_repository?(private_repo)
  end

  context "Internal repos" do
    test "are readable by org admins" do
      assert @admin.can_read_internal_repository?(@internal_repo)
    end

    test "are readable by enterprise members" do
      assert @member.can_read_internal_repository?(@internal_repo)
    end


    test "are readable by billing managers" do
      assert @billing_manager.can_read_internal_repository?(@internal_repo)
    end

    test "are not readable by non-enterprise members" do
      refute @rando.can_read_internal_repository?(@internal_repo)
    end

    test "are not readable by soft deleted org members" do
      perform_enqueued_jobs only: [SoftDeleteOrganizationRepositoriesJob] do
        @org2.soft_delete!
      end
      refute @member.can_read_internal_repository?(@internal_repo)
    end
  end
end

class User
  def can_read_internal_repository?(repo)
    ::Permissions::Enforcer.authorize(
      action: :test_macro_actor_can_read_internal_repository,
      actor: self,
      subject: repo
    ).allow?
  end
end
