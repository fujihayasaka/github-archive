# typed: true
# frozen_string_literal: true

require "test_helper"

class UserRepositoryTemplateDependencyTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @admin = create(:user)
    @user = create(:user)
    @user2 = create(:user)

    @template_user = create :user
    @private_template = create(:private_repository, template: true, owner: @template_user)
  end

  context "#recently_used_template_repository_ids" do
    test "returns recently cloned templates for user" do
      template1 = create(:repository, template: true)
      template2 = create(:repository, template: true)
      create(:repository_clone, cloning_user: @user, template_repository: template1)
      create(:repository_clone, cloning_user: @user, template_repository: template2)
      other_clone = create(:repository_clone) # not by target user

      result = @user.recently_used_template_repository_ids

      assert_includes result, template1.id
      assert_includes result, template2.id
      refute_includes result, other_clone.template_repository_id
    end

    test "returns an empty list for an organization" do
      org = create(:organization, admin: @user)
      template = create(:repository, template: true)
      create(:repository_clone, cloning_user: @user, template_repository: template)

      result = org.recently_used_template_repository_ids

      assert_empty result
    end
  end

  context "#repository_templates_for" do
    test "includes public template that was recently cloned by the user" do
      template = create(:repository, template: true)
      viewer = nil
      create(:repository_clone, cloning_user: @user, template_repository: template)

      result = @user.repository_templates_for(viewer)

      assert_includes result, template
    end

    test "omits private template that was recently cloned by the user when viewer can't see it" do
      private_template = create(:private_repository, template: true)
      viewer = nil
      create(:repository_clone, cloning_user: @user, template_repository: private_template)

      result = @user.repository_templates_for(viewer)

      refute_includes result, private_template
    end

    test "includes private template that was recently cloned by the user when viewer can see it" do
      private_template = create(:private_repository, template: true)
      viewer = create(:user)
      private_template.add_member(viewer)
      create(:repository_clone, cloning_user: @user, template_repository: private_template)

      result = @user.repository_templates_for(viewer)

      assert_includes result, private_template
    end

    test "omits disabled template" do
      template = create(:repository, template: true)
      template.access.disable("size", User.ghost)
      viewer = nil
      create(:repository_clone, cloning_user: @user, template_repository: template)

      result = @user.repository_templates_for(viewer)

      refute_includes result, template
    end

    if GitHub.spamminess_check_enabled?
      test "omits spammy template" do
        spammer = create(:spammy_user)
        template = create(:repository, template: true, owner: spammer)
        viewer = nil

        result = spammer.repository_templates_for(viewer)

        refute_includes result, template
      end

      test "includes spammy template when it's owned by the viewer" do
        spammer = create(:spammy_user)
        template = create(:repository, template: true, owner: spammer)

        result = spammer.repository_templates_for(spammer)

        assert_includes result, template
      end
    end

    test "omits template that the user hasn't cloned and does not own" do
      template = create(:repository, template: true)
      viewer = nil

      result = @user.repository_templates_for(viewer)

      refute_includes result, template
    end

    test "includes public template created by the user" do
      template = create(:repository, template: true, owner: @user)
      viewer = nil

      result = @user.repository_templates_for(viewer)

      assert_includes result, template
    end

    test "includes public template owned by org user belongs to" do
      org = create(:organization)
      org.add_member(@user)
      template = create(:repository, template: true, owner: org)
      viewer = nil

      result = @user.repository_templates_for(viewer)

      assert_includes result, template
    end

    test "includes internal template owned by org user belongs to" do
      org = create(:enterprise_linked_organization)
      # stub this to return false so we can call update_default_repository_permission
      org.stubs(:updating_default_repository_permission?).returns(false)
      org.update_default_repository_permission(:none, actor: @admin)
      org.add_member(@user)

      # add a public and internal repo template to the org
      public_template = create(:repository, template: true, owner: org)
      internal_template = create(:internal_repository, template: true, owner: org)

      # anonymous viewers can't see the internal template, but they can see the public template
      # if they somehow(?) manage to obtain a user context of the org or a user in the org
      assert_same_elements [public_template], org.repository_templates_for(nil)
      assert_same_elements [public_template], @user.repository_templates_for(nil)

      # the org can see the org's templates
      assert_same_elements [internal_template, public_template], org.repository_templates_for(org)

      # org member in user's context will see the org's internal template
      assert_same_elements [internal_template, public_template], @user.repository_templates_for(@user)

      # org member in the org's context will see the internal template
      assert_same_elements [internal_template, public_template], org.repository_templates_for(@user)

      # users not in the org cannot see the internal template
      assert_empty @user2.repository_templates_for(@user2)

      # but non-org-members can see public templates if they somehow(?) have an org context
      assert_same_elements [public_template], org.repository_templates_for(@user2)
    end

    test "omits internal template cloned by user who has since left the org" do
      org = create(:enterprise_linked_organization)
      org.stubs(:updating_default_repository_permission?).returns(false)
      org.update_default_repository_permission(:none, actor: @admin)
      org.add_member(@user)

      internal_template = create(:internal_repository, template: true, owner: org)

      create(:repository_clone, cloning_user: @user, template_repository: internal_template)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        org.remove_member(@user)
      end

      assert_empty @user.repository_templates_for(@user)
    end

    test "includes private template owned by org user belongs to when viewer can see it" do
      org = create(:organization)
      org.add_member(@user)
      private_template = create(:private_repository, template: true, owner: org)
      viewer = @user

      result = @user.repository_templates_for(viewer)

      assert private_template.readable_by?(viewer),
        "viewer must be able to access the private repo or the test doesn't make sense"
      assert_includes result, private_template
    end

    test "omits private template owned by org user belongs to when viewer can't see it" do
      org = create(:organization)
      org.add_member(@user)
      private_template = create(:private_repository, template: true, owner: org)
      viewer = create(:user)

      result = @user.repository_templates_for(viewer)

      refute_includes result, private_template
    end

    test "omits private template created by the user when viewer can't see it" do
      private_template = create(:private_repository, template: true, owner: @user)
      viewer = nil

      result = @user.repository_templates_for(viewer)

      refute_includes result, private_template
    end

    test "includes private template created by the user when viewer can see it" do
      private_template = create(:private_repository, template: true, owner: @user)
      viewer = create(:user)
      private_template.add_member(viewer)

      result = @user.repository_templates_for(viewer)

      assert_includes result, private_template
    end

    test "omits non-public templates from unauthorized organizations" do
      viewer = create(:user)
      org_authorized = create(:organization)
      org_authorized.add_member(viewer)

      org_unauthorized = create(:organization)
      org_unauthorized.add_member(viewer)

      private_authorized_template = create(:private_repository, template: true, owner: org_authorized)
      public_authorized_template = create(:repository, template: true, owner: org_authorized)
      private_unauthorized_template = create(:private_repository, template: true, owner: org_unauthorized)
      public_unauthorized_template = create(:repository, template: true, owner: org_unauthorized)

      cap_filter = cap_unauthorizing_filter([org_unauthorized])

      result = viewer.repository_templates_for(viewer, cap_filter: cap_filter)

      if GitHub.flipper[:repos_all_public_templates].enabled?
        assert_same_elements result, [private_authorized_template, public_authorized_template, public_unauthorized_template]
      else
        assert_same_elements result, [private_authorized_template, public_authorized_template]
      end
    end

    test "includes template owned by user but forked from private org repo" do
      viewer = create(:user)
      org = create(:organization)
      org.add_member(viewer)

      template = create(:private_repository, template: true, owner: org)
      org.allow_private_repository_forking(actor: org)

      forked_template = create(:fork_repository, forker: viewer, fork_repo: template)

      assert_equal forked_template.owner, viewer
      assert_equal forked_template.organization, org

      cap_filter = cap_unauthorizing_filter([org])

      result = viewer.repository_templates_for(viewer, cap_filter: cap_filter)

      assert_same_elements result, [forked_template]
    end

    test "does not return private repos when user is nil" do
      org = create(:organization)

      template_private = create(:private_repository, template: true, owner: org)
      template_public = create(:repository, template: true, owner: org)

      cap_filter = cap_unauthorizing_filter([])

      result = org.repository_templates_for(nil, cap_filter: cap_filter)

      assert_same_elements result, [template_public]
    end
  end

  context "#quick_has_repository_templates?" do
    test "true if viewer has access to the user template" do
      viewer = @template_user
      assert @template_user.quick_has_repository_templates?(viewer)
    end

    test "true if user has templates even if viewer has no access to them" do
      viewer = create :user
      assert @template_user.quick_has_repository_templates?(viewer)
    end

    test "false if viewer has no templates reachable" do
      user = create :user
      viewer = user
      refute user.quick_has_repository_templates?(viewer)
    end

    test "true if viewer has access to recently used templates" do
      template1 = create(:repository, template: true)
      template2 = create(:repository, template: true)
      create(:repository_clone, cloning_user: @template_user, template_repository: template1)
      create(:repository_clone, cloning_user: @template_user, template_repository: template2)
      other_clone = create(:repository_clone) # not by target user

      assert @template_user.quick_has_repository_templates?(@template_user)
    end
  end
end
