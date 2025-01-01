# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationDiscussionConfigTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:verified_user)
    @org = create(:organization, admins: [@user])
    @repo = create(:repository, organization: @org)
    @private_repo = create(:private_repository, organization: @org)
  end

  context "validations" do
    test "requires repository" do
      config = OrganizationDiscussionConfig.new(
        organization: @org,
        repository: nil,
      )

      refute_predicate config, :valid?
      assert_equal ["Repository can't be blank"], config.errors.full_messages
    end

    test "requires organization" do
      config = OrganizationDiscussionConfig.new(
        organization: nil,
        repository: @repo,
      )

      refute_predicate config, :valid?
      assert_equal ["Organization can't be blank"], config.errors.full_messages
    end

    test "repository cannot be already in use" do
      other_org = create(:organization)
      create(:organization_discussion_config, repository: @repo)

      config = OrganizationDiscussionConfig.new(
        organization: other_org,
        repository: @repo,
      )

      refute_predicate config, :valid?
      assert_equal ["Repository has already been taken"], config.errors.full_messages
    end
  end

  context "discussion enablement" do
    test "enables discussions for repository without discussions already enabled" do
      refute_predicate @repo, :discussions_on?
      create(:organization_discussion_config, organization: @org, repository: @repo, actor: @user)
      assert_predicate @repo, :discussions_on?
    end

    test "does not enable discussions for repository that already is enabled" do
      @repo.turn_on_discussions(actor: @user)
      assert_predicate @repo, :discussions_on?

      Repository.any_instance.expects(:turn_on_discussions).never
      create(:organization_discussion_config, organization: @org, repository: @repo, actor: @user)
    end
  end

  context "hydro events for public repos", skip_enterprise: true do
    test "logs event on creation" do
      create(:organization_discussion_config,
        organization: @org,
        repository: @repo,
        actor: @user
      )

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization_id: @org.id,
        public_repository_id: @repo&.id,
        actor_id: @user.id,
        action: :ORG_DISCUSSION_CREATED
      }

      assert_hydro_published(message, schema: "github.discussions.v2.OrgDiscussions")
      assert_hydro_messages(count: 1, schema: "github.discussions.v2.OrgDiscussions")
    end

    test "logs event on update" do
      organization_discussion = create(:organization_discussion_config,
        organization: @org,
        repository: @repo,
        actor: @user
      )
      new_repo = create(:repository, organization: @org)

      reset_hydro

      organization_discussion.update(repository: new_repo)

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization_id: @org.id,
        public_repository_id: new_repo.id,
        actor_id: @user.id,
        action: :ORG_DISCUSSION_UPDATED
      }

      assert_hydro_published(message, schema: "github.discussions.v2.OrgDiscussions")
      assert_hydro_messages(count: 1, schema: "github.discussions.v2.OrgDiscussions")
    end

    test "logs event on deletion" do
      organization_discussion = create(:organization_discussion_config,
        organization: @org,
        repository: @repo,
        actor: @user
      )
      reset_hydro
      organization_discussion.destroy

      message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        organization_id: @org.id,
        public_repository_id: @repo&.id,
        actor_id: @user.id,
        action: :ORG_DISCUSSION_DELETED
      }

      assert_hydro_published(message, schema: "github.discussions.v2.OrgDiscussions")
      assert_hydro_messages(count: 1, schema: "github.discussions.v2.OrgDiscussions")
    end
  end
end
