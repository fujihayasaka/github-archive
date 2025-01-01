# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectStatusTest < GitHub::TestCase
  fixtures do
    @admin = create(:verified_user)
    @owner = create(:organization, login: "projects-org", admin: @admin)

    @memex_project_for_org = create(:memex_project, owner: @owner)
    @status = create(:memex_project_status, memex_project: @memex_project_for_org)
  end

  def build_previous_status_update
    MemexProjectStatus.build_for_project(@memex_project_for_org, @owner, ActionController::Parameters.new({
      status_id: "459eafad",
      start_date: "2023-01-01",
      target_date: "2023-01-14",
      body: "The project is off to a great start!"
    }))
  end

  def build_empty_status_update
    MemexProjectStatus.build_for_project(@memex_project_for_org, @owner, ActionController::Parameters.new({
      status_id: nil,
      start_date: "",
      target_date: "",
      body: "Nothing to see here"
    }))
  end

  test "status_options is an array" do
    assert_kind_of Array, MemexProjectStatus.status_options
  end

  context "validates options in status_value" do
    test "returns error if status_id is not a status option" do
      @status.status_value = { status_id: "not_a_status" }.to_json

      refute @status.valid?
      assert_equal "status is invalid", @status.errors.full_messages.first
    end

    test "does not return error if status_id is a status option" do
      @status.status_value = { status_id: "459eafad" }.to_json

      assert @status.valid?
    end

    test "returns error if status_value does not contain one of needed keys" do
      @status.status_value = { not_a_key: "not_a_value" }.to_json

      refute @status.valid?
      assert_equal "invalid extra input was provided", @status.errors.full_messages.first
    end

    test "does not return error if status_value contains one of needed keys" do
      @status.status_value = { status_id: "459eafad" }.to_json

      assert @status.valid?
    end

    test "returns error if start_date is an invalid date string" do
      @status.status_value = { start_date: "a" }.to_json

      refute @status.valid?
      assert_equal "Start date not a recognized date format", @status.errors.full_messages.first
    end

    test "returns error if target_date is an invalid date string" do
      @status.status_value = { target_date: "a" }.to_json

      refute @status.valid?
      assert_equal "Target date not a recognized date format", @status.errors.full_messages.first
    end
  end

  context "validates presence of status_value and body" do
    test "returns error if status_value and body is not present" do
      @status.status_value = nil
      @status.body = nil

      refute @status.valid?
      assert_equal "status, start date, target date or body must be present", @status.errors.full_messages.first
    end

    test "does not return error if status_value is present" do
      @status.body = nil

      assert @status.valid?
    end

    test "does not return error if body is present" do
      @status.status_value = nil

      assert @status.valid?
    end
  end

  test "returns status_id error if status_id is not a status option" do
    @status.status_value = { status_id: "not_a_status" }.to_json

    refute @status.valid?
    assert_equal "status is invalid", @status.errors.full_messages.first
  end

  test "does not create status update if project is a template" do
    project = create(:memex_project, owner: @owner)
    project.create_template!

    status = project.memex_project_statuses.new(body: "testing", creator: @admin)

    refute status.valid?
    assert_equal "Cannot perform this action on a template", status.errors.full_messages.first
  end

  context "self.build_for_project" do
    test "can create a new status matching the expected shape" do
      update = MemexProjectStatus.build_for_project(@memex_project_for_org, @owner, ActionController::Parameters.new({
        status_id: "459eafad",
        start_date: "2023-01-01",
        target_date: "2023-01-14",
        body: "The project is off to a great start!"
      }))

      assert update.valid?

      expected_status_value = {
        status_id: "459eafad",
        start_date: "2023-01-01",
        target_date: "2023-01-14",
      }

      assert_equal update.body, "The project is off to a great start!"
      assert_equal update.status_value, expected_status_value.to_json
    end
  end

  context "to_hash" do
    test "returns the expected data" do
      update = MemexProjectStatus.build_for_project(@memex_project_for_org, @owner, ActionController::Parameters.new({
        status_id: "459eafad",
        start_date: "2023-01-01",
        target_date: "2023-01-14",
        body: "The project is off to a great start!"
      }))

      assert update.valid?

      hash = update.to_hash(@owner, nil)

      expected_status_value = {
        status_id: "459eafad",
        start_date: "2023-01-01",
        target_date: "2023-01-14",
        status: {
          id: "459eafad",
          name: "On track",
          nameHtml: "On track",
          color: "GREEN",
          description: "This project is on track with no risks."
        },
      }

      assert_equal hash[:body], "The project is off to a great start!"
      assert_equal hash[:status_value].to_json, expected_status_value.to_json
    end

    test "returns user_hidden is true if user is spammy", spammy_only: true do
      spammy_user = create(:verified_user, spammy: true)
      @owner.add_member(spammy_user)

      status = create(:memex_project_status, memex_project: @memex_project_for_org, creator: spammy_user)
      hash = status.to_hash(spammy_user, nil)

      assert_equal hash[:user_hidden], true
    end
  end

  test "user_hidden is true if created by spammy user", spammy_only: true do
    spammy_user = create(:verified_user, spammy: true)
    @owner.add_member(spammy_user)

    status = create(:memex_project_status, memex_project: @memex_project_for_org, creator: spammy_user)

    assert_predicate status, :user_hidden
  end

  context "start_date" do
    # This double-write should be removed https://github.com/github/memex/issues/18179
    test "Saves the start date in both the status value and on the column" do
      assert_equal "2023-01-01", build_previous_status_update.start_date.iso8601
      assert_equal "2023-01-01", JSON.parse(build_previous_status_update.status_value)["start_date"]

      assert_nil build_empty_status_update.start_date
      assert_empty JSON.parse(build_empty_status_update.status_value)["start_date"]
    end
  end

  context "target_date" do
    # This double-write should be removed https://github.com/github/memex/issues/18179
    test "Saves the target date in both the status value and on the column" do
      assert_equal "2023-01-14", build_previous_status_update.target_date.iso8601
      assert_equal "2023-01-14", JSON.parse(build_previous_status_update.status_value)["target_date"]

      assert_nil build_empty_status_update.target_date
      assert_empty JSON.parse(build_empty_status_update.status_value)["target_date"]
    end
  end

  context "status_name_html" do
    test "Extracts the status_name_html from status_value" do
      assert_equal "On track", build_previous_status_update.status_name_html
      assert_nil build_empty_status_update.status_name_html
    end
  end

  context "notify_on" do
    test "create" do
      enable_feature_flag(:memex_status_updates_notifications)

      params = ActionController::Parameters.new(
        status_id: "459eafad",
        start_date: "2023-01-01",
        target_date: "2023-01-14",
        body: "The project is off to a great start!"
      )
      update = MemexProjectStatus.build_for_project(@memex_project_for_org, @owner, params)

      expected_attributes = {
        actor: update.creator,
        memex_project_status: update,
      }
      GlobalInstrumenter.expects(:instrument).with("memex_project_status.create", expected_attributes)
      update.save!
    end

    test "update when webhooks enabled" do
      enable_feature_flag(:memex_status_updates_notifications)

      params = ActionController::Parameters.new(
        status_id: "459eafad",
        start_date: "2023-01-01",
        target_date: "2023-01-14",
        body: "The project is off to a great start!"
      )
      update = MemexProjectStatus.build_for_project(@memex_project_for_org, @owner, params)
      update.save!

      expected_attributes = {
        actor: update.creator,
        memex_project_status: update,
        previous_body: "The project is off to a great start!",
        current_body: "The project is off to a great start! I'm so excited!",
      }
      GlobalInstrumenter.expects(:instrument).with("memex_project_status.update", expected_attributes)
      update.update!(body: "The project is off to a great start! I'm so excited!")
    end
  end

  context "permalink" do
    test "returns nil when new record" do
      memex_project_status = MemexProjectStatus.new

      assert_predicate memex_project_status, :new_record?
      assert_nil memex_project_status.permalink
    end

    test "when include_host is false returns the status permalink as a path" do
      admin = create(:verified_user)
      organization = create(:organization, login: "status-tests", admin: admin)
      memex_project = create(:memex_project, owner: organization)
      memex_project_status = create(:memex_project_status, memex_project: memex_project)
      expected_permalink = "/orgs/status-tests/projects/1?pane=info&statusUpdateId=#{memex_project_status.id}"

      assert_equal expected_permalink, memex_project_status.permalink(include_host: false)
    end

    test "when include_host is true returns the status permalink as a full url" do
      admin = create(:verified_user)
      organization = create(:organization, login: "status-tests", admin: admin)
      memex_project = create(:memex_project, owner: organization)
      memex_project_status = create(:memex_project_status, memex_project: memex_project)
      expected_permalink = "https://github.com/orgs/status-tests/projects/1?pane=info&statusUpdateId=#{memex_project_status.id}"

      assert_equal expected_permalink, memex_project_status.permalink(include_host: true)
    end
  end

  context "user" do
    test "async_user returns the creator" do
      assert_equal @status.creator, @status.async_user.sync
    end

    test "returns the creator" do
      assert_equal @status.creator, @status.user
    end
  end

  context "organization" do
    test "async_organization returns the project owner when owned by an organization" do
      admin = create(:verified_user)
      organization = create(:organization, login: "status-tests", admin: admin)
      memex_project = create(:memex_project, owner: organization)
      memex_project_status = create(:memex_project_status, memex_project: memex_project)

      assert_predicate memex_project, :org_owned?
      assert_equal organization, memex_project_status.async_organization.sync
    end

    test "async_organization is blank when user owned project" do
      admin = create(:verified_user)
      memex_project = create(:memex_project, owner: admin)
      memex_project_status = create(:memex_project_status, memex_project: memex_project)

      assert_predicate memex_project, :user_owned?
      assert_nil memex_project_status.async_organization.sync
    end

    test "returns the project owner when owned by an organization" do
      admin = create(:verified_user)
      organization = create(:organization, login: "status-tests", admin: admin)
      memex_project = create(:memex_project, owner: organization)
      memex_project_status = create(:memex_project_status, memex_project: memex_project)

      assert_predicate memex_project, :org_owned?
      assert_equal organization, memex_project_status.organization
    end

    test "is blank when user owned project" do
      admin = create(:verified_user)
      memex_project = create(:memex_project, owner: admin)
      memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)

      assert_predicate memex_project, :user_owned?
      assert_nil memex_project_status.organization
    end
  end

  context "safe_creator" do
    test "returns status update creator" do
      admin = create(:verified_user)
      memex_project = create(:memex_project, owner: admin)
      memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)

      assert_equal admin, memex_project_status.safe_creator
    end

    test "returns ghost user when creator no longer exists" do
      admin = create(:verified_user)
      memex_project = create(:memex_project, owner: admin)
      memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)
      admin.destroy

      assert_equal User.ghost, memex_project_status.reload.safe_creator
    end
  end

  context "modifying_user" do
    test "returns contextual actor" do
      admin = create(:verified_user, login: "memex-admin")
      member = create(:verified_user, login: "memex-member")
      memex_project = create(:memex_project, owner: admin)
      memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)

      GitHub.context.push(actor_id: member.id) do
        assert_equal member, memex_project_status.modifying_user
      end
    end

    test "returns creator if contextual actor does not exist" do
      admin = create(:verified_user, login: "memex-admin")
      memex_project = create(:memex_project, owner: admin)
      memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)

      GitHub.context.push(actor_id: -1) do
        assert_equal memex_project_status.creator, memex_project_status.modifying_user
      end
    end

    test "returns creator by default" do
      admin = create(:verified_user, login: "memex-admin")
      memex_project = create(:memex_project, owner: admin)
      memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)

      assert_equal admin, memex_project_status.modifying_user
    end
  end

  context "message_id" do
    test "returns blank when new record" do
      memex_project_status = MemexProjectStatus.new

      assert_predicate memex_project_status, :new_record?
      assert_nil memex_project_status.message_id
    end

    test "returns generated message id" do
      admin = create(:verified_user, login: "creator")
      memex_project = create(:memex_project, owner: admin)
      memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)
      expected_message_id = "<creator/projects/#{memex_project.id}/statuses/#{memex_project_status.id}@#{GitHub.urls.host_name}>"

      assert_equal expected_message_id, memex_project_status.message_id
    end
  end

  test "async_notifications_list returns project owner" do
    admin = create(:verified_user, login: "creator")
    memex_project = create(:memex_project, owner: admin)
    memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)

    assert_equal admin, memex_project_status.async_notifications_list.sync
  end

  test "notifications_thread returns MemexProject" do
    admin = create(:verified_user, login: "creator")
    memex_project = create(:memex_project, owner: admin)
    memex_project_status = create(:memex_project_status, creator: admin, memex_project: memex_project)

    assert_equal memex_project, memex_project_status.notifications_thread
  end

  test "notifications_author returns creator" do
    admin = create(:verified_user, login: "creator")
    member = create(:verified_user, login: "member")
    memex_project = create(:memex_project, owner: admin)
    memex_project_status = create(:memex_project_status, creator: member, memex_project: memex_project)

    assert_equal member, memex_project_status.notifications_author
  end

  context "status_id_to_enum_string" do
    test "maps status option ids to enum" do
      assert_equal "INACTIVE", MemexProjectStatus.status_id_to_enum_string("8be313fb")
      assert_equal "ON_TRACK", MemexProjectStatus.status_id_to_enum_string("459eafad")
      assert_equal "AT_RISK", MemexProjectStatus.status_id_to_enum_string("366655d6")
      assert_equal "OFF_TRACK", MemexProjectStatus.status_id_to_enum_string("04201a9a")
      assert_equal "COMPLETE", MemexProjectStatus.status_id_to_enum_string("c77b75a3")
    end
  end

  context "status_enum_string_to_id" do
    test "maps status option enum to status id" do
      assert_equal "8be313fb", MemexProjectStatus.status_enum_string_to_id("INACTIVE")
      assert_equal "459eafad", MemexProjectStatus.status_enum_string_to_id("ON_TRACK")
      assert_equal "366655d6", MemexProjectStatus.status_enum_string_to_id("AT_RISK")
      assert_equal "04201a9a", MemexProjectStatus.status_enum_string_to_id("OFF_TRACK")
      assert_equal "c77b75a3", MemexProjectStatus.status_enum_string_to_id("COMPLETE")
    end
  end
end
