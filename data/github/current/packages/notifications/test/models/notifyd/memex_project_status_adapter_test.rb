# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class MemexProjectStatusAdapterTest < GitHub::TestCase
    include NotifydTestHelper

    fixtures do
      @admin = create(:user)
      @organization = create(:organization, admin: @admin)
      @member = create(:verified_user).tap { |u| @organization.add_member(u) }
      @team = create(:team, organization: @organization, name: "Foo bar", slug: "foo-bar")
      @team.add_member(@member, adder: @admin)
      @organization_memex_project = create(:memex_project, owner: @organization)
      @user_memex_project = create(:memex_project)
    end

    context "validating subject" do
      test "matches when MemexProject is not deleted" do
        memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
        adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

        refute_predicate @organization_memex_project, :deleted?, "expected MemexProject to not have been deleted"
        assert_predicate adapter, :matches?, "expected adapter to have a match"
      end

      test "does not matche when MemexProject is deleted" do
        memex_project = create(:memex_project, :deleted)
        memex_project_status = create(:memex_project_status, memex_project: memex_project)
        adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

        assert_predicate memex_project, :deleted?, "expected MemexProject to have been deleted"
        refute_predicate adapter, :matches?, "expected adapter to not have a match"
      end
    end

    test "notify_feature_flag returns notifyd_memex_project_status_notify" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      expected_feature_flag = GitHub.flipper[:notifyd_memex_project_status_notify]
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_equal expected_feature_flag, adapter.notify_feature_flag
    end

    test "notification_id returns MemexProjectStatus permalink without host" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      refute_equal memex_project_status.permalink, adapter.notification_id
      assert_equal memex_project_status.permalink(include_host: false), adapter.notification_id
    end

    test "repository_id is blank" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_nil adapter.repository_id, "expected repository_id to be nil as MemexProjects do not belong to a repository"
    end

    test "#authzd_attributes" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_equal @organization_memex_project.permissions_wrapper.serialized_subject_attributes, adapter.authzd_attributes
    end

    test "actor is creator when create operation" do
      memex_project_status = create(:memex_project_status, creator: @admin, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status, {
        operation: Notifyd::Operations::MemexProjectStatusOperation::Create.serialize,
        actor_id: nil,
      })

      refute_equal @member, memex_project_status.creator
      assert_equal @admin, adapter.actor
    end

    test "actor is creator when unknown operation" do
      memex_project_status = create(:memex_project_status, creator: @admin, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status, {
        operation: Notifyd::Operations::MemexProjectStatusOperation::Unknown.serialize,
        actor_id: nil,
      })

      refute_equal @member, memex_project_status.creator
      assert_equal @admin, adapter.actor
    end

    test "actor is loaded from the context on update" do
      memex_project_status = create(:memex_project_status, creator: @admin, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status, {
        operation: Notifyd::Operations::MemexProjectStatusOperation::Update.serialize,
        actor_id: @member.id,
      })

      refute_equal @member, memex_project_status.creator
      assert_equal @member, adapter.actor
    end

    test "saml_enforcement for organization owned MemexProject" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)
      expected_saml_enforcement = {
        organization_id: @organization.id,
      }

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal expected_saml_enforcement, adapter.saml_enforcement
    end

    test "saml_enforcement is blank for user owned MemexProject" do
      memex_project_status = create(:memex_project_status, memex_project: @user_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_predicate memex_project_status.memex_project, :user_owned?
      assert_nil adapter.saml_enforcement
    end

    test "mobile_layout is blank" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_nil adapter.mobile_layout, "expected mobile_layout to be nil as MemexProjectStatuses do not have mobile support"
    end

    test "email_layout is renders successfully for organization owned project" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_kind_of Notifyd::Proto::Layouts::Email::Basic, adapter.email_layout
    end

    test "email_layout is renders successfully for user owned project" do
      memex_project_status = create(:memex_project_status, memex_project: @user_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_predicate memex_project_status.memex_project, :user_owned?
      assert_kind_of Notifyd::Proto::Layouts::Email::Basic, adapter.email_layout
    end

    test "related_topics for organization owned project" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)
      expected_related_topics = [
        {
          type: Notifyd::MemexProjectStatusAdapter::THREAD_TYPE,
          value: memex_project_status.memex_project_id.to_s,
        },
        {
          type: "organization",
          value: memex_project_status.memex_project.owner_id.to_s,
        },
      ]

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal expected_related_topics, adapter.related_topics
    end

    test "related_topics for user owned project" do
      memex_project_status = create(:memex_project_status, memex_project: @user_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)
      expected_related_topics = [
        {
          type: Notifyd::MemexProjectStatusAdapter::THREAD_TYPE,
          value: memex_project_status.memex_project_id.to_s,
        },
      ]

      assert_predicate memex_project_status.memex_project, :user_owned?
      assert_equal expected_related_topics, adapter.related_topics
    end

    test "explicit_recipients for organization owned project subscribes project creator as author" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status, {
        current_body: memex_project_status.body,
        operation: Notifyd::Operations::MemexProjectStatusOperation::Create.serialize,
      })
      expected_explicit_recipients = [
        {
          reason: "author",
          users: [@organization_memex_project.creator],
        },
        {
          reason: "state_change",
          users: [memex_project_status.creator],
        }
      ]

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal expected_explicit_recipients, adapter.explicit_recipients
    end

    test "explicit_recipients for user owned project subscribes project creator as author" do
      memex_project_status = create(:memex_project_status, memex_project: @user_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status, {
        current_body: memex_project_status.body,
        operation: Notifyd::Operations::MemexProjectStatusOperation::Create.serialize,
      })
      expected_explicit_recipients = [
        {
          reason: "author",
          users: [@user_memex_project.creator],
        },
        {
          reason: "state_change",
          users: [memex_project_status.creator],
        }
      ]

      assert_predicate memex_project_status.memex_project, :user_owned?
      assert_equal expected_explicit_recipients, adapter.explicit_recipients
    end

    test "explicit_recipients can mention users" do
      memex_project_status = create(:memex_project_status, creator: @admin, body: "Hi @#{@member.display_login}", memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status, {
        current_body: memex_project_status.body,
        operation: Notifyd::Operations::MemexProjectStatusOperation::Create.serialize,
      })
      expected_explicit_recipients = [
        {
          reason: "mention",
          users: [@member],
        },
        {
          reason: "author",
          users: [@organization_memex_project.creator],
        },
        {
          reason: "state_change",
          users: [memex_project_status.creator],
        },
      ]

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal expected_explicit_recipients, adapter.explicit_recipients
    end

    test "explicit_recipients can mention teams" do
      memex_project_status = create(:memex_project_status, creator: @admin, body: "Hi @#{@team.combined_slug}", memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status, {
        current_body: memex_project_status.body,
        operation: Notifyd::Operations::MemexProjectStatusOperation::Create.serialize,
      })
      expected_explicit_recipients = [
        {
          reason: "team_mention",
          users: [@member],
        },
        {
          reason: "author",
          users: [@organization_memex_project.creator],
        },
        {
          reason: "state_change",
          users: [memex_project_status.creator],
        },
      ]

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal expected_explicit_recipients, adapter.explicit_recipients
    end

    test "attributes for organization owned project subscribes project creator as author" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)
      expected_attributes = [
        {
          name: "thread_participant_activity",
          value: "true",
        },
        {
          name: "thread_type",
          value: "memex_project",
        },
      ]

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal expected_attributes, adapter.attributes
    end

    test "attributes for user owned project subscribes project creator as author" do
      memex_project_status = create(:memex_project_status, memex_project: @user_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)
      expected_attributes = [
        {
          name: "thread_participant_activity",
          value: "true",
        },
        {
          name: "thread_type",
          value: "memex_project",
        },
      ]

      assert_predicate memex_project_status.memex_project, :user_owned?
      assert_equal expected_attributes, adapter.attributes
    end

    test "owner_id for organization owned project subscribes project creator as author" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal @organization_memex_project.owner_id, adapter.owner_id
    end

    test "owner_id for user owned project subscribes project creator as author" do
      memex_project_status = create(:memex_project_status, memex_project: @user_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_predicate memex_project_status.memex_project, :user_owned?
      assert_equal @user_memex_project.owner_id, adapter.owner_id
    end

    test "owner_type for organization owned project subscribes project creator as author" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal :organization, adapter.owner_type
    end

    test "owner_type for user owned project subscribes project creator as author" do
      memex_project_status = create(:memex_project_status, memex_project: @user_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)

      assert_predicate memex_project_status.memex_project, :user_owned?
      assert_equal :user, adapter.owner_type
    end

    test "trigger returns operation" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status, {
        operation: Notifyd::Operations::MemexProjectStatusOperation::Create.serialize,
      })

      assert_equal "create", adapter.trigger
    end

    test "feature_switches for organization owned project only notifies subscribers" do
      memex_project_status = create(:memex_project_status, memex_project: @organization_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)
      expected_feature_switches = {
        notify_actor: false,
        notify_subscribers: true,
      }

      assert_predicate memex_project_status.memex_project, :org_owned?
      assert_equal expected_feature_switches, adapter.feature_switches
    end

    test "feature_switches for user owned project only notifies subscribers" do
      memex_project_status = create(:memex_project_status, memex_project: @user_memex_project)
      adapter = Notifyd::MemexProjectStatusAdapter.new(memex_project_status)
      expected_feature_switches = {
        notify_actor: false,
        notify_subscribers: true,
      }

      assert_predicate memex_project_status.memex_project, :user_owned?
      assert_equal expected_feature_switches, adapter.feature_switches
    end
  end
end
