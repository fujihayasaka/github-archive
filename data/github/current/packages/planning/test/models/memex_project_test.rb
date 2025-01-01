# typed: true
# frozen_string_literal: true

require "test_helper"

class MemexProjectTest < GitHub::TestCase
  include StringFromBinaryTestHelper
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @org = create(:organization)
    @user = create(:verified_user).tap { |u| @org.add_member(u) }
    @other_user = create(:verified_user).tap { |u| @org.add_member(u) }
    @non_member = create(:verified_user)
    @repo = create(:private_repository, owner: @org)
    @private_repo = create(:private_repository, owner: create(:organization))
    @milestone = create(:milestone, repository: @repo)
    @issue = create(:issue, repository: @repo, user: @user, milestone: @milestone)
    @private_issue = create(:issue, repository: @private_repo)
    @pull = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)

    @org_memex_creator = create(:verified_user).tap { |u| @org.add_member(u) }
    @org_memex = create(:memex_project, owner: @org, creator: @org_memex_creator)
    @user_memex = create(:memex_project, owner: @user)
    @user_public_memex = create(:memex_project, owner: @user, public: true)

    unless GitHub.enterprise?
      @emu = create(:emu)
      @emu_business = @emu.enterprise_managed_business
      @emu_org = create(:organization, business: @emu_business)
    end

    @github_org = create(:organization, login: "github")

    @staffer = create(:staff_admin_user, login: "staffer", plan: "medium", email: "staffer@example.com")
    @staffer.emails.first.verify!
    @github_org.add_member(@staffer)
    @github_org.add_member(@user)
    @org.add_member(@staffer)
  end

  include MemexHelpers
  include PrioritizationHelpers
  include HydroTestHelpers

  setup do
    GitHub.flipper[:tasklist_block].disable
    GitHub.flipper[:memex_paginated_archive].disable
    GitHub.flipper[:memex_table_without_limits].disable
    GitHub.flipper[:memex_without_limits_kill_switch].disable
    GitHub.flipper[:memex_mwl_new_projects].disable

    GitHub.context.push(actor_id: @other_user.id)
    @org.enable_organization_projects(actor: @user)
    GitHub.flipper[:memex_no_public_emu_projects].enable
  end

  def serialize_message(payload)
    {
      project: Hydro::EntitySerializer.memex_project(payload[:project]),
      actor: Hydro::EntitySerializer.user(payload[:actor]),
      project_owner: Hydro::EntitySerializer.user(payload[:project_owner]),
      action: payload[:action],
      request_context: Hydro::EntitySerializer.request_context(payload[:request_context])
    }
  end

  def serialize_user_generated_content_message(payload)
    {
      **payload,
      actor: Hydro::EntitySerializer.user(payload[:actor]),
      owner: Hydro::EntitySerializer.user(payload[:owner]),
      request_context: Hydro::EntitySerializer.request_context(payload[:request_context]),
      title: Hydro::EntitySerializer.specimen_data(payload[:title]),
      content: Hydro::EntitySerializer.specimen_data(payload[:content])
    }
  end

  context "excluded_default_columns" do
    test "does not exclude issue type column for organization-owned projects when issue_types feature flag is enabled" do
      GitHub.flipper[:issue_types].enable(@org)

      actual_excluded_default_columns = MemexProject.excluded_default_columns(@user, @org)

      assert_predicate @org, :organization?, "expected user to be an organization"
      assert @org.feature_enabled?(:issue_types), "issue_types should be enabled for owner"
      assert_empty actual_excluded_default_columns, "Expected no excluded default columns"
    end

    test "does not exclude issue type column for organization-owned projects when issue_types feature flag is disabled" do
      GitHub.flipper[:issue_types].disable(@org)

      actual_excluded_default_columns = MemexProject.excluded_default_columns(@user, @org)

      assert_predicate @org, :organization?, "expected user to be an organization"
      refute @org.feature_enabled?(:issue_types), "issue_types should not be enabled for owner"
      assert_empty actual_excluded_default_columns, "Expected no excluded default columns"
    end

    test "excludes issue type column for user-owned projects even if issue_types feature flag is enabled" do
      GitHub.flipper[:issue_types].enable(@user)

      actual_excluded_default_columns = MemexProject.excluded_default_columns(@user, @user)
      expected_excluded_default_columns = [MemexProjectColumn::TYPE_COLUMN_NAME]

      refute_predicate @user, :organization?, "expected user to not be an organization"
      assert @user.feature_enabled?(:issue_types), "issue_types should be enabled for owner"
      assert_equal expected_excluded_default_columns, actual_excluded_default_columns, "expected issue type column to be excluded"
    end
  end

  context "validations" do
    test "disallows the empty string as a title" do
      memex = build(:memex_project, title: "")

      refute memex.save
      assert_includes memex.errors.full_messages, "Title can't be blank"
    end

    test "disallows string with only whitespace a title" do
      memex = build(:memex_project, title: "   ")

      refute memex.save
      assert_includes memex.errors.full_messages, "Title can't be blank"
    end

    test "disallows a title longer than the maximum allowable size" do
      memex = build(:memex_project, title: "x" * (MemexProject::TITLE_BYTESIZE_LIMIT + 1))

      refute memex.save
      assert_includes memex.errors.full_messages, "Title is too long (maximum is 256 characters)"
    end

    test "allows a UTF string in the title" do
      memex = build(:memex_project, title: "other encoding".dup.tap { |t| t.force_encoding("ISO-8859-1") })
      memex.save
      assert_equal Encoding::UTF_8, memex.title.encoding
    end

    test "supports emoji for title" do
      memex = create(:memex_project, title: "we ❤️ emojis")

      assert_multibyte_tracked_changes(memex, :title)
    end

    test "requires an owner" do
      memex = build(:memex_project, owner: nil)

      refute memex.save
      assert_includes memex.errors.full_messages, "Owner can't be blank"
    end

    test "requires a number" do
      memex = build(:memex_project, number: nil)
      memex.stubs(:set_number)

      refute memex.valid?
      assert_includes memex.errors.full_messages, "Number can't be blank"
    end

    test "requires number to be unique for the owner" do
      org = create(:organization)
      existing_memex = create(:memex_project, owner: org)
      new_memex = build(:memex_project, owner: org, number: existing_memex.number)

      refute new_memex.save
      assert_includes new_memex.errors.full_messages, "Number has already been taken"
    end

    test "disallows a short description longer than the maximum allowable size" do
      memex = build(:memex_project, title: "Title", short_description: "x" * (MemexProject::SHORT_DESCRIPTION_LIMIT + 1))

      refute memex.save
      assert_includes memex.errors.full_messages, "Short description is too long (maximum is 300 characters)"
    end

    test "requires a creator" do
      memex = build(:memex_project, creator: nil)

      refute memex.save
      assert_includes memex.errors.full_messages, "Creator can't be blank"
    end

    test "requires the creator to have a verified email" do
      memex = build(:memex_project, creator: create(:user))
      refute memex.creator.emails.verified.any?

      refute memex.save
      assert_includes memex.errors.full_messages, "Creator must have a verified email address"
    end unless GitHub.enterprise?

    test "does not require the creator to have a verified email within Enterprise", enterprise_only: true do
      memex = build(:memex_project, creator: create(:user))
      refute memex.creator.emails.verified.any?

      assert memex.save
    end

    test "requires default columns to be saved alongside the memex itself" do
      memex = build(:memex_project, omit_default_columns: true)
      assert_empty memex.memex_project_columns

      refute memex.save
      assert_includes memex.errors.full_messages, "Default columns must be saved at the same time"
    end

    test "allows default columns to be saved at the same time as memex itself" do
      memex = build(:memex_project, omit_default_columns: true)
      memex.memex_project_columns.build(MemexProject.default_column_attributes)
      refute_empty memex.memex_project_columns

      assert memex.save
      refute_empty memex.reload.memex_project_columns
    end

    test "user-owned project complains if even one default column is not being saved alongside the memex itself" do
      memex = build(:memex_project, owner: @user, omit_default_columns: true)
      default_column_attributes = MemexProject.default_column_attributes(excluding: [MemexProjectColumn::TYPE_COLUMN_NAME])
      memex.memex_project_columns.build(default_column_attributes[0...-1])

      assert_predicate memex, :user_owned?, "expected user-owned project"
      refute memex.save
      assert_includes memex.errors.full_messages, "Default columns must be saved at the same time"
    end

    test "org-owned project complains if even one default column is not being saved alongside the memex itself" do
      memex = build(:memex_project, owner: @org, omit_default_columns: true)
      default_column_attributes = MemexProject.default_column_attributes
      memex.memex_project_columns.build(default_column_attributes[0...-1])

      assert_predicate memex, :org_owned?, "expected org-owned project"
      refute memex.save
      assert_includes memex.errors.full_messages, "Default columns must be saved at the same time"
    end

    test "requires that orgs have projects enabled" do
      @org.disable_organization_projects(actor: @user)
      memex = build(:memex_project, owner: @org)
      refute_predicate memex, :valid?
      assert_includes memex.errors.full_messages,
        "Owner has disabled projects for this organization"
    end

    test "org projects do not impact user owner projects" do
      @org.disable_organization_projects(actor: @user)
      memex = build(:memex_project, owner: @user)
      assert_predicate memex, :valid?
    end

    test "with feature flag disabled, allows creation of a public project that is owned by an EMU", skip_enterprise: true do
      GitHub.flipper[:memex_no_public_emu_projects].disable
      project = build(:memex_project, public: true, owner: @emu)
      assert project.valid?
      assert project.save
    end

    test "disallows creation of a public project that is owned by an EMU", skip_enterprise: true do
      project = build(:memex_project, public: true, owner: @emu)
      refute project.valid?
      assert_includes(
        project.errors.full_messages,
        "Owner cannot own a public project because they are an enterprise-managed user or organization"
      )
    end

    test "disallows creation of a public project that is owned by an EMU-enabled org", skip_enterprise: true do
      project = build(:memex_project, public: true, owner: @emu_org)
      refute project.valid?
      assert_includes(
        project.errors.full_messages,
        "Owner cannot own a public project because they are an enterprise-managed user or organization"
      )
    end

    test "disallows making a project public when that project is owned by an EMU", skip_enterprise: true do
      project = create(:memex_project, owner: @emu)
      refute_predicate project, :public?
      assert_predicate project, :valid?

      project.public = true

      refute_predicate project, :valid?
      refute project.save
      assert_includes(
        project.errors.full_messages,
        "Owner cannot own a public project because they are an enterprise-managed user or organization"
      )
    end

    test "disallows making a project public when that project is owned by an EMU-enabled org", skip_enterprise: true do
      project = create(:memex_project, owner: @emu_org)
      refute_predicate project, :public?
      assert_predicate project, :valid?

      project.public = true

      refute_predicate project, :valid?
      refute project.save
      assert_includes(
        project.errors.full_messages,
        "Owner cannot own a public project because they are an enterprise-managed user or organization"
      )
    end
  end

  context "#org_owned?" do
    test "true when owner is of type org" do
      memex = build(:memex_project, owner: @org)
      assert_predicate memex, :org_owned?
    end

    test "false when owner is not of type org" do
      memex = build(:memex_project, owner: @user)
      refute_predicate memex, :org_owned?
    end
  end

  context "has_reached_items_limit?" do
    test "true when the number of items has reached the limit" do
      fake_limit = 3
      MemexProjectItem.stub_const(:PER_PAGE_LIMIT, fake_limit) do
        memex = create(:memex_project)
        fake_limit.times do
          refute memex.has_reached_items_limit?
          memex_item = create(:memex_project_item, memex_project: memex)
        end
        assert memex.has_reached_items_limit?
      end
    end
  end

  context "#to_hash" do
    test "dumps relevant attributes of the object" do
      # Fri, March 6, 2020 8pm UTC.
      fixed_created_at = Time.utc(2020, 3, 06, 20, 00, 00)

      memex = travel_to fixed_created_at do
        create(
          :memex_project,
          title: "The `Master Plan`",
          description: "The way it will go down.",
          short_description: "`tldr` https://github.com",
        )
      end

      expected_hash = {
        closedAt: nil,
        createdAt: "2020-03-06T20:00:00Z",
        description: "The way it will go down.",
        shortDescription: "`tldr` https://github.com",
        shortDescriptionHtml: '`tldr` <a href="https://github.com">https://github.com</a>',
        id: memex.id,
        public: false,
        number: memex.number,
        title: "The `Master Plan`",
        titleHtml: "The <code>Master Plan</code>",
        updatedAt: "2020-03-06T20:00:00Z",
        isTemplate: false,
        templateId: nil,
      }

      assert_equal expected_hash, memex.to_hash
    end

    test "dumps relevant template attributes" do
      memex = create(:memex_project)
      memex_template = create(:memex_template, memex_project: memex)

      assert_equal true, memex.to_hash[:isTemplate]
      assert_equal memex_template.id, memex.to_hash[:templateId]
    end

    test "does not include inactive templates in templates scope" do
      organization = create(:organization)
      active_memex_project = create(:memex_project, owner: organization)
      active_memex_template = create(:memex_template, memex_project: active_memex_project, active: true)
      inactive_memex_project = create(:memex_project, owner: organization)
      inactive_memex_template = create(:memex_template, memex_project: inactive_memex_project, active: false)

      assert_equal [active_memex_project], organization.memex_projects.templates
    end

    test "includes inactive templates in without_templates scope" do
      organization = create(:organization)
      memex_project = create(:memex_project, owner: organization)
      disabled_memex_project = create(:memex_project, owner: organization)
      active_memex_project = create(:memex_project, owner: organization)
      active_memex_template = create(:memex_template, memex_project: active_memex_project, active: true)
      inactive_memex_project = create(:memex_project, owner: organization)
      inactive_memex_template = create(:memex_template, memex_project: inactive_memex_project, active: false)

      assert_same_elements [memex_project, disabled_memex_project, inactive_memex_project], organization.memex_projects.without_templates
    end

    test "to_suggestion_hash returns specific form" do
      memex = create(
        :memex_project,
        title: "The Master Plan",
        description: "The way it will go down.",
        short_description: "tldr"
      )

      owner_login = memex.owner.organization? ? memex.owner.safe_profile_name : memex.owner.display_login
      expected_hash = {
        id: memex.id,
        name: memex.name,
        owner: owner_login,
        selected: false,
        template: false,
      }

      assert_equal expected_hash, memex.to_suggestion_hash
    end

    test "to_suggestion_hash returns specific form when project is a template" do
      memex = create(
        :memex_project,
        title: "The Master Plan",
        description: "The way it will go down.",
        short_description: "tldr"
      )
      memex_template = create(:memex_template, memex_project: memex)

      owner_login = memex.owner.organization? ? memex.owner.safe_profile_name : memex.owner.display_login
      expected_hash = {
        id: memex.id,
        name: memex.name,
        owner: owner_login,
        selected: false,
        template: true,
      }

      assert_equal expected_hash, memex.to_suggestion_hash
    end
  end

  context "#consistency_metrics" do
    test "returns nil if the viewer is a non-github staff", skip_enterprise: true do
      refute_predicate @user, :employee?, "expected the user to not be a GitHub staff"

      [@org_memex, @user_memex].each do |memex|
        assert_nil memex.consistency_metrics(viewer: @user)
      end
    end

    test "returns consistency metrics for github staff only", skip_enterprise: true do
      expected_hash = {
        consistency: nil,
        inconsistencyThreshold: MemexProjectElasticsearchConsistency::INCONSISTENCY_THRESHOLD
      }

      [@org_memex, @user_memex].each do |memex|
        assert_equal expected_hash, memex.consistency_metrics(viewer: @staffer)
      end
    end
  end

  context "#set_number" do
    test "generates a unique sequence per owner" do
      admin = create(:verified_user)
      org_one, org_two = create_list(:organization, 2, admin: admin)
      user_one, user_two = create_list(:user, 3)

      assert_equal 1, create(:memex_project, owner: org_one).number
      assert_equal 2, create(:memex_project, owner: org_one).number
      assert_equal 3, create(:memex_project, owner: org_one).number
      assert_equal 4, create(:memex_project, owner: org_one).number
      assert_equal 5, create(:memex_project, owner: org_one).number

      assert_equal 1, create(:memex_project, owner: org_two).number
      assert_equal 2, create(:memex_project, owner: org_two).number

      assert_equal 1, create(:memex_project, owner: user_one).number
      assert_equal 2, create(:memex_project, owner: user_one).number
      assert_equal 3, create(:memex_project, owner: user_one).number

      assert_equal 1, create(:memex_project, owner: user_two).number
      assert_equal 2, create(:memex_project, owner: user_two).number
    end

    test "shares organization sequence with projects" do
      org = create(:organization)
      assert_equal 1, create(:memex_project, owner: org).number
      assert_equal 2, create(:project, owner: org).number
      assert_equal 3, create(:memex_project, owner: org).number
      assert_equal 4, create(:project, owner: org).number
      assert_equal 5, create(:memex_project, owner: org).number
    end

    test "shares user sequence with projects" do
      user = create(:user)
      assert_equal 1, create(:memex_project, owner: user).number
      assert_equal 2, create(:project, owner: user).number
      assert_equal 3, create(:memex_project, owner: user).number
      assert_equal 4, create(:project, owner: user).number
      assert_equal 5, create(:memex_project, owner: user).number
    end

    test "initializes the sequence at the largest memex number if it was missing" do
      org = create(:organization)
      create(:memex_project, owner: org, number: 5)
      create(:project, owner: org).update(number: 1)

      # Be sure there are no sequences
      ApplicationRecord::Domain::Sequences.connection.delete(Arel.sql("DELETE FROM sequences"))

      assert_equal 6, create(:memex_project, owner: org).number
      assert_equal 7, create(:project, owner: org).number
    end

    test "returns an html preview of MD title" do
      org = create(:organization)
      memex = create(:memex_project, owner: org)
      memex.update(title: "The `Master Plan`")

      assert_equal  "The `Master Plan`", memex.title
      assert_equal "The <code>Master Plan</code>", memex.title_html
    end

    test "initializes the sequence at the largest project number if it was missing" do
      org = create(:organization)
      create(:memex_project, owner: org, number: 1)
      create(:project, owner: org).update(number: 5)

      # Be sure there are no sequences
      ApplicationRecord::Domain::Sequences.connection.delete(Arel.sql("DELETE FROM sequences"))

      assert_equal 6, create(:memex_project, owner: org).number
      assert_equal 7, create(:project, owner: org).number
    end
  end

  context "#columns" do
    test "returns only default columns for a newly created memex" do
      expected_default_columns = MemexProjectColumn.default_columns(excluding: [MemexProjectColumn::TYPE_COLUMN_NAME])
      assert_equal expected_default_columns.map(&:name), create(:memex_project).columns.map(&:name)
    end

    test "returns default columns (including new column(s) when feature flag(s) is enabled) for a newly created memex" do
      GitHub.flipper[:tasklist_block].enable
      expected_default_columns = MemexProjectColumn.default_columns(excluding: [MemexProjectColumn::TYPE_COLUMN_NAME])
      assert_equal expected_default_columns.map(&:name), create(:memex_project).columns.map(&:name)
    end

    test "caches the list of columns for a memex" do
      memex = create(:memex_project)
      columns_on_first_retrieval = memex.columns
      refute_predicate columns_on_first_retrieval, :empty?

      columns_on_second_retrieval = assert_query_count(0) { memex.columns }

      assert_equal columns_on_first_retrieval, columns_on_second_retrieval
    end

    test "invalidates the cached list of columns when the memex object is reloaded" do
      memex = create(:memex_project)
      columns_on_first_retrieval = memex.columns
      refute_predicate columns_on_first_retrieval, :empty?

      # We expect one query to reload the memex, and a second to reload the columns.
      columns_on_second_retrieval = assert_query_count(2) do
        memex.reload.columns
      end

      assert_equal columns_on_first_retrieval, columns_on_second_retrieval
    end

    test "returns columns ordered by position ascending" do
      result = create(:memex_project).columns
      refute_empty result
      prior_position = result.first.position
      result.drop(1).each do |column|
        assert_operator prior_position, :<, column.position, "expected columns to be returned in ascending order " \
          "by position, but got column in position #{prior_position} before position #{column.position}"
        prior_position = column.position
      end
    end
  end

  context "#flipper_id" do
    test "it returns the flipper id" do
      memex = create(:memex_project)

      assert_equal("MemexProject:#{memex.id}", memex.flipper_id)
    end
  end

  context "#reorder_columns" do
    test "orders columns according to the given array" do
      memex = create(:memex_project)
      new_column_names = memex.reload.columns.reverse.map(&:name)
      refute_equal new_column_names, memex.columns.map(&:name)

      assert memex.reorder_columns(memex.columns.reverse)

      assert_equal new_column_names, memex.reload.columns.map(&:name)
    end

    test "does not do any reordering if a column is otherwise invalid" do
      memex = create(:memex_project)
      original_column_names = memex.reload.columns.map(&:name)
      memex.columns[0].name = nil

      refute memex.reorder_columns(memex.columns[1..-1] + [memex.columns[0]])

      assert_equal original_column_names, memex.reload.columns.map(&:name)
    end
  end

  context ".create_with_associations" do
    test "does not save the memex without a title" do
      error = assert_raises(ArgumentError) do
        memex = MemexProject.create_with_associations(owner: @org, creator: @user)
      end

      assert_equal "Must provide :title", error.message
    end

    test "increments metric on ActiveRecord::ConnectionFailed" do
      MemexProject.expects(:throttle_writes_with_retry).once.raises(ActiveRecord::ConnectionFailed)

      memex = MemexProject.create_with_associations(owner: @org, creator: @user, title: "Brand new")

      refute_predicate memex, :persisted?
      assert_dogstats_increment 1, "memex.create_with_associations.creation_failure", tags: ["error:ActiveRecord::ConnectionFailed"]
    end

    test "saves a memex with just a title" do
      memex = MemexProject.create_with_associations(owner: @org, creator: @user, title: "Brand new")

      assert_predicate memex, :valid?, (memex.errors.full_messages +
        memex.memex_project_columns.flat_map { |col| col.errors.full_messages } +
        memex.workflows.flat_map { |wf| wf.errors.full_messages }).to_sentence
      assert_predicate memex, :persisted?
      assert_equal MemexProjectColumn.default_columns.length, memex.memex_project_columns.length

      status_column = memex.columns.detect(&:status?)
      refute_nil status_column
      assert_predicate status_column, :persisted?
      expected_workflows = MemexProject.default_persisted_workflow_attributes(creator: @user,
        status_column: T.must(status_column))
      assert_equal expected_workflows.length, memex.workflows.length

      assert_equal "Brand new", memex.title
    end

    test "user-owned project does not include Type column" do
      memex = MemexProject.create_with_associations(owner: @user, creator: @user, title: "Brand new")

      assert_predicate memex, :persisted?
      assert_predicate memex, :user_owned?
      actual_default_columns_count = MemexProjectColumn.default_columns(excluding: [MemexProjectColumn::TYPE_COLUMN_NAME]).count
      assert_equal actual_default_columns_count, memex.memex_project_columns.length
    end

    test "organization-owned projects include Type column" do
      memex = MemexProject.create_with_associations(owner: @org, creator: @user, title: "Brand new")

      assert_predicate memex, :persisted?
      assert_predicate memex, :org_owned?
      actual_default_columns_count = MemexProjectColumn.default_columns.count
      assert_equal actual_default_columns_count, memex.memex_project_columns.length
    end

    test "includes Status with the default columns saved with a memex" do
      memex = MemexProject.create_with_associations(owner: @org, creator: @user, title: "Brand new")

      assert_predicate memex, :valid?, memex.errors.full_messages.join(", ")
      assert_predicate memex, :persisted?
      assert memex.memex_project_columns.length > 1

      status_column = memex.status_column
      refute_nil status_column
      assert_predicate status_column, :persisted?
      assert_predicate status_column, :visible?
      assert_equal ["Todo", "In Progress", "Done"], T.must(status_column).settings["options"].map { |o| o["name"] }
    end

    test "creates draft item with title body and assignees and denormalized data" do
      memex = MemexProject.create_with_associations(owner: @org, creator: @user, title: "Some new project")
      item = memex.build_draft_issue(
        creator: @user, title: "My title",
        body: "My body", assignees: [@user, @other_user]
      )
      item.save!

      item = T.must(memex.memex_project_items.first)

      assert_equal "DraftIssue", item.content_type
      assert_equal "My title", item.content.title
      assert_same_elements [@user.login, @other_user.login], T.must(item).content.assignees.pluck(:login)

      assert_memex_item_is_denormalized(memex, item)
    end

    test "limits queries made for creating an org-owned Memex board" do
      assert_query_count_per_table({
        business_organization_memberships: 3,
        businesses: 2,
        configuration_entries: 1,
        key_values: 1,
        memex_project_columns: 65,
        memex_project_views: 7,
        memex_project_workflows: 13,
        memex_projects: 3,
        sequences: 17,
        user_emails: GitHub.enterprise? ? 0 : 1,
        users: 12,
      }) do
        MemexProject.create_with_associations(owner: @org, creator: @user, title: "Some new project")
      end
    end

    test "limits queries made for creating a user-owned Memex board" do
      assert_query_count_per_table({
        key_values: 1,
        memex_project_columns: 60,
        memex_project_views: 7,
        memex_project_workflows: 13,
        memex_projects: 3,
        sequences: 17,
        user_emails: GitHub.enterprise? ? 0 : 1,
        users: 12,
      }) do
        MemexProject.create_with_associations(owner: @user, creator: @user, title: "My New Project")
      end
    end

    test "enables and persists Merged, Closed, auto-close workflows when a memex is created" do
      memex = MemexProject.create_with_associations(owner: @org, creator: @user, title: "Brand new")

      status_column = T.let(memex.reload.status_column, MemexProjectColumn)
      workflows = memex.workflows

      assert_equal 3, workflows.count

      closed_workflow = T.must(workflows.first)
      assert_equal "closed", closed_workflow.trigger_type
      assert closed_workflow.enabled
      assert_equal "set_field", closed_workflow.actions[0].action_type
      assert_equal T.must(status_column).id, closed_workflow.actions[0].arguments["fieldId"]
      assert_equal T.must(status_column).settings["options"].last["id"],
        closed_workflow.actions[0].arguments["fieldOptionId"]

      auto_close_workflow = T.must(workflows.find_by(trigger_type: :project_item_column_update))
      assert auto_close_workflow.enabled
      assert_equal "get_project_items", auto_close_workflow.actions[0].action_type
      assert_equal "close_item", auto_close_workflow.actions[1].action_type
      assert_equal status_column.id, auto_close_workflow.actions[0].arguments["fieldId"]
      assert_equal status_column.settings["options"].last["id"], auto_close_workflow.actions[0].arguments["fieldOptionId"]
    end

    test "enables memex_table_without_limits FF for internal project for staff user with memex_mwl_new_projects enabled", skip_enterprise: true do
      GitHub.flipper[:memex_mwl_new_projects].enable

      memex = MemexProject.create_with_associations(owner: @github_org, creator: @staffer, title: "Brand new", with_mwl_enabled: true)
      assert memex.feature_enabled?(:memex_table_without_limits)
    end

    test "does not enable memex_table_without_limits FF for internal project for staff user with memex_mwl_new_projects disabled", skip_enterprise: true do
      GitHub.flipper[:memex_mwl_new_projects].disable

      memex = MemexProject.create_with_associations(owner: @github_org, creator: @staffer, title: "Brand new", with_mwl_enabled: true)
      refute memex.feature_enabled?(:memex_table_without_limits)
    end

    test "does not enable memex_table_without_limits FF for non-internal project", skip_enterprise: true do
      GitHub.flipper[:memex_mwl_new_projects].enable

      memex = MemexProject.create_with_associations(owner: @org, creator: @staffer, title: "Brand new", with_mwl_enabled: true)
      refute memex.feature_enabled?(:memex_table_without_limits)
    end

    test "does not enable memex_table_without_limits FF for non-staff user", skip_enterprise: true do
      GitHub.flipper[:memex_mwl_new_projects].enable

      memex = MemexProject.create_with_associations(owner: @github_org, creator: @user, title: "Brand new", with_mwl_enabled: true)
      refute memex.feature_enabled?(:memex_table_without_limits)
    end

    test "does not enable memex_table_without_limits FF for eligible project if with_mwl_enabled: false", skip_enterprise: true do
      GitHub.flipper[:memex_mwl_new_projects].enable

      memex = MemexProject.create_with_associations(owner: @github_org, creator: @staffer, title: "Brand new", with_mwl_enabled: false)
      refute memex.feature_enabled?(:memex_table_without_limits)
    end
  end

  context "#status_column" do
    test "returns the Status column for the project if one exists" do
      status_column = @user_memex.memex_project_columns.find_by(name: MemexProjectColumn::STATUS_COLUMN_NAME)
      refute_nil status_column
      assert_equal status_column, @user_memex.status_column

      status_column.destroy!
      assert_nil @user_memex.reload.status_column
    end

    test "does not make an additional query when all columns are already loaded" do
      status_column = @user_memex.memex_project_columns.find_by(name: MemexProjectColumn::STATUS_COLUMN_NAME)
      refute_nil status_column

      @user_memex.memex_project_columns.to_a # load the relation of all columns
      assert_predicate @user_memex.association(:memex_project_columns), :loaded?
      refute_predicate @user_memex.association(:status_column), :loaded?

      assert_query_count(0) do
        assert_equal status_column, @user_memex.status_column
      end
    end
  end

  context "close project" do
    test "disables all workflows when project is closed" do
      memex = create(
        :memex_project,
        title: "The Master Plan",
        description: "The way it will go down.",
        short_description: "tldr",
        creator: @user,
        owner: @org
      )

      workflows = [
        MemexProjectWorkflow.default_closed_workflow_attributes(
          status_column: memex.status_column,
          creator: memex.creator,
          enabled: true
        )
      ]
      memex.workflows.create(workflows)
      assert memex.workflows.any?(&:enabled)

      perform_enqueued_jobs(only: [MemexProjectDisableAllWorkflowsJob]) do
        now = DateTime.new(2021, 05, 06)
        memex.update(closed_at: now)
      end

      refute memex.reload.workflows.all?(&:enabled)
    end

    test "doesn't disable any workflows when project is re-opened" do
      memex = create(
        :memex_project,
        title: "The Master Plan",
        description: "The way it will go down.",
        short_description: "tldr",
        creator: @user,
        owner: @org,
        closed_at: Time.now
      )

      workflows = [
        MemexProjectWorkflow.default_closed_workflow_attributes(
          status_column: memex.status_column,
          creator: memex.creator,
          enabled: true
        )
      ]
      memex.workflows.create(workflows)
      assert memex.workflows.any?(&:enabled)

      perform_enqueued_jobs(only: [MemexProjectDisableAllWorkflowsJob]) do
        memex.update(closed_at: nil)
      end

      assert memex.reload.workflows.any?(&:enabled)
    end

    test "doesn't disable any workflows when other property was updated" do
      memex = create(
        :memex_project,
        title: "The Master Plan",
        description: "The way it will go down.",
        short_description: "tldr",
        creator: @user,
        owner: @org,
        closed_at: Time.now
      )

      workflows = [
        MemexProjectWorkflow.default_closed_workflow_attributes(
          status_column: memex.status_column,
          creator: memex.creator,
          enabled: true
        )
      ]
      memex.workflows.create(workflows)
      assert memex.workflows.any?(&:enabled)

      perform_enqueued_jobs(only: [MemexProjectDisableAllWorkflowsJob]) do
        memex.update(title: "New title")
      end

      assert memex.reload.workflows.any?(&:enabled)
    end
  end

  context "#destroy" do
    test "destroys dependent records on destroy" do
      memex = create(:memex_project, :with_default_workflows)
      memex_item = create(:memex_project_item, memex_project: memex)
      memex_column = create(:memex_project_column, memex_project: memex)
      memex_column_value = create(:memex_project_column_value, column: memex_column, item: memex_item)
      memex_chart = create(:memex_project_chart, memex_project: memex)
      memex_template = create(:memex_template, memex_project: memex)
      memex.grant_role(@non_member, Role.project_writer_role)

      refute_empty memex.workflows
      refute_empty UserRole.where(target_id: memex.id, role: Role.project_writer_role, actor_id: @non_member.id)

      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
        memex.destroy
      end

      assert_nil MemexProject.find_by(id: memex.id)
      assert_nil MemexProjectItem.find_by(id: memex_item.id)
      assert_nil MemexProjectColumn.find_by(id: memex_column.id)
      assert_nil MemexProjectColumnValue.find_by(id: memex_column_value.id)
      assert_nil MemexProjectChart.find_by(id: memex_chart.id)
      assert_nil MemexTemplate.find_by(id: memex_template.id)
      assert_empty MemexProjectWorkflow.where(memex_project_id: memex.id)
      assert_empty UserRole.where(target_id: memex.id, role: Role.project_writer_role, actor_id: @non_member.id)
    end
  end

  context "#save_with_priority!" do
    test "validates and then raises when attempting to save an invalid item" do
      memex = create(:memex_project)
      item = memex.build_item(creator: @user, issue_or_pull: @issue)
      item.creator = nil
      refute item.valid?

      assert_raises(ActiveRecord::RecordInvalid) do
        memex.save_with_priority!(item)
      end
    end

    test "sets priority value on first item in a project" do
      memex = create(:memex_project)
      item = memex.build_item(creator: @user, issue_or_pull: @issue)
      assert_nil item.virtual_priority

      # Make sure that we never invoke the legacy priority system.
      memex.expects(:prioritize).never
      memex.expects(:prioritize_dependent!).never

      assert memex.save_with_priority!(item)

      item.reload
      refute_nil item.virtual_priority
    end

    test "sets priority value on later item in a project when project has been rebalanced" do
      memex = create(:memex_project)
      existing_items = create_list(:memex_project_item, 2, memex_project: memex)
      memex.rebalance!(association: :memex_project_items, mode: GitHub::Prioritizable::Context::RebalanceMode::Dual)
      memex.reload

      item = memex.build_item(creator: @user, issue_or_pull: @issue)
      assert_nil item.virtual_priority

      # Make sure that we never invoke the legacy priority system.
      memex.expects(:prioritize).never
      memex.expects(:prioritize_dependent!).never

      assert memex.save_with_priority!(item)

      item.reload
      refute_nil item.virtual_priority
    end

    test "suppresses item hydro events from being published when passed suppress_hydro_events: true" do
      memex = create(:memex_project)
      item = create(:memex_project_item, memex_project: memex)

      assert memex.save_with_priority!(item, position: :top, suppress_hydro_events: true)
      assert_hydro_messages(count: 0, schema: "github.memex.v0.ProjectItemMetadataUpdate")
    end
  end

  context "#save_column_with_priority" do
    test "reposition a column to a lower position cascade update next columns to shift their position properly" do
      # arrange
      memex = create(:memex_project)
      memex_column_one = create(:memex_project_column, memex_project: memex)
      memex_column_two = create(:memex_project_column, memex_project: memex)
      memex_column_three = create(:memex_project_column, memex_project: memex)
      memex_column_four = create(:memex_project_column, memex_project: memex)
      columns = [
        memex_column_one,
        memex_column_two,
        memex_column_three,
        memex_column_four,
      ]

      initial_positions = columns.each_with_object({}) { |column, positions| positions[column.id] = column.position }

      # act
      memex.save_column_with_priority(memex_column_three, **{ after: memex_column_one })
      columns.each { |column| column.reload }

      # assert
      assert_equal initial_positions[memex_column_one.id],  memex_column_one.position
      assert_equal initial_positions[memex_column_two.id],  memex_column_three.position
      assert_equal initial_positions[memex_column_three.id],  memex_column_two.position
      assert_equal initial_positions[memex_column_four.id],  memex_column_four.position
    end

    test "reposition a column to a higher position cascade update previously columns to shift their position properly" do
      # arrange
      memex = create(:memex_project)
      memex_column_one = create(:memex_project_column, memex_project: memex)
      memex_column_two = create(:memex_project_column, memex_project: memex)
      memex_column_three = create(:memex_project_column, memex_project: memex)
      memex_column_four = create(:memex_project_column, memex_project: memex)
      columns = [
        memex_column_one,
        memex_column_two,
        memex_column_three,
        memex_column_four,
      ]

      initial_positions = columns.each_with_object({}) { |column, positions| positions[column.id] = column.position }

      # act
      memex.save_column_with_priority(memex_column_one, **{ after: memex_column_three })
      columns.each { |column| column.reload }

      # assert
      assert_equal initial_positions[memex_column_one.id],  memex_column_two.position
      assert_equal initial_positions[memex_column_two.id],  memex_column_three.position
      assert_equal initial_positions[memex_column_three.id],  memex_column_one.position
      assert_equal initial_positions[memex_column_four.id],  memex_column_four.position
    end

    test "reposition a column to the 'top' position places it at position 1" do
      # arrange
      memex = create(:memex_project)
      memex_column_one = create(:memex_project_column, memex_project: memex)
      memex_column_two = create(:memex_project_column, memex_project: memex)
      memex_column_three = create(:memex_project_column, memex_project: memex)
      memex_column_four = create(:memex_project_column, memex_project: memex)
      columns = [
        memex_column_one,
        memex_column_two,
        memex_column_three,
        memex_column_four,
      ]

      initial_positions = columns.each_with_object({}) { |column, positions| positions[column.id] = column.position }

      # act
      success = memex.save_column_with_priority(memex_column_two, **{ position: :top })
      columns.each { |column| column.reload }

      # assert
      assert success
      assert_equal initial_positions[memex_column_one.id] + 1,  memex_column_one.position
      assert_equal 1,  memex_column_two.position
      assert_equal initial_positions[memex_column_three.id],  memex_column_three.position
      assert_equal initial_positions[memex_column_four.id],  memex_column_four.position
    end
  end

  context "#prioritized_scope" do
    test "returns a scope that orders items by virtual priority" do
      memex = create(:memex_project)

      memex_item_one = create(:memex_project_item, memex_project: memex, content: create(:issue), priority: 10, priority_numerator: 1, priority_denominator: 1)
      memex_item_two = create(:memex_project_item, memex_project: memex, content: create(:issue), priority: 1, priority_numerator: 10, priority_denominator: 1)
      archived_item = create(:memex_project_item, memex_project: memex, content: create(:issue), priority: 20, priority_numerator: 20, priority_denominator: 1, archived_at: 2.days.ago, archiver: @user)

      expected_items = [memex_item_two, memex_item_one]
      actual_items = memex.prioritized_scope(:memex_project_items)
      refute_includes actual_items.map(&:virtual_priority), nil
      assert_equal expected_items, actual_items
      refute_includes actual_items, archived_item
    end
  end

  context "#async_prioritized_scope" do
    test "returns a promise for scope that orders items by virtual priority" do
      memex = create(:memex_project)

      memex_item_one = create(:memex_project_item, memex_project: memex, content: create(:issue), priority: 10, priority_numerator: 1, priority_denominator: 1)
      memex_item_two = create(:memex_project_item, memex_project: memex, content: create(:issue), priority: 1, priority_numerator: 10, priority_denominator: 1)
      archived_item = create(:memex_project_item, memex_project: memex, content: create(:issue), priority: 20, priority_numerator: 20, priority_denominator: 1, archived_at: 2.days.ago, archiver: @user)

      expected_items = [memex_item_two, memex_item_one]
      actual_items = memex.async_prioritized_scope(:memex_project_items).sync
      refute_includes actual_items.map(&:virtual_priority), nil
      assert_equal expected_items, actual_items
      refute_includes actual_items, archived_item
    end
  end

  context "#build_item" do
    # This is a test for a "bug" where failing to pass an issue/PR or draft issue title
    # into build_item would cause the function to crash previously due to calling
    # build_denormalized_column_values on a nil value. This was fixed by making the function
    # throw an error, so we can ensure better type safety.
    test "throws an error if no draft issue title or issue/pull request is passed" do
      memex = create(:memex_project)
      assert_raises_with_message(ArgumentError, "Must provide either an issue, pull request, or draft issue title (received neither)") do
        item = memex.build_item(creator: @user)
      end
    end
  end

  context "Intrumentation" do
    test "instruments project creation" do
      GitHub.context.push(actor_id: @user.id)
      events = subscribe "project.create"
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        memex = create(
          :memex_project,
          title: "The Master Plan",
          short_description: "The way it will rise up.",
          description: "The way it will go down.",
          creator: @user,
          owner: @org,
          public: false,
        )

        expected_payload = {
          project_id: memex.id,
          project_name: memex.name,
          project_kind: "MemexProject",
          performed_at: Time.now,
          public_project: false,
          actor: @user.login,
          actor_id: @user.id,
          org_id: @org.id,
          org: @org.login,
        }

        expected_hydro_message = serialize_message(
          project: memex,
          project_owner: memex.owner,
          actor: @user,
          action: :create,
          request_context: GitHub.context.to_hash
        )
        assert_hydro_published(expected_hydro_message, schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)

        assert_hydro_published(serialize_user_generated_content_message({
          actor: @user,
          content_type: :MEMEX_PROJECT,
          content_database_id: memex.id,
          title: memex.title,
          content: "#{memex.short_description}\n#{memex.description}",
          owner: memex.owner
        }), ignore_extra_keys: true, schema: "github.platform_health.v1.UserGeneratedContent")

        assert event = events.pop, "an event was expected"
        assert_equal "project.create", event.name
        assert_equal expected_payload[:project_id], event.payload[:project_id]
        assert_equal expected_payload[:project_name], event.payload[:project_name]
        assert_equal expected_payload[:project_kind], event.payload[:project_kind]
        assert_equal expected_payload[:performed_at], event.payload[:performed_at]
        assert_equal expected_payload[:public_project], event.payload[:public_project]
        assert_equal expected_payload[:actor], event.payload[:actor]
        assert_equal expected_payload[:actor_id], event.payload[:actor_id]
        assert_equal expected_payload[:org_id], event.payload[:org_id]
        assert_equal expected_payload[:org], event.payload[:org]
      end
    end

    test "does not emit project.close event if project is updated" do
      events = subscribe "project.close"
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org
        )

        memex.update(title: "new title")
        assert_nil events.pop, "a close event was not expected"
      end
    end

    test "does not emit project.close if a closed project is updated" do
      events = subscribe "project.close"
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        closed_memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org,
          closed_at: Time.now
        )
        closed_memex.update(title: "new title")
        assert_nil events.pop, "a close event was not expected"
      end
    end

    test "does not emit project.close if a closed project is updated with nil timestamp" do
      events = subscribe "project.close"
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        closed_memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org,
          closed_at: now
        )

        closed_memex.update(closed_at: nil)
        assert_nil events.pop, "a close event was not expected"
      end
    end

    test "instruments project closed" do
      events = subscribe "project.close"
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org,
        )

        memex.update(closed_at: Time.now)

        expected_payload = {
          project_id: memex.id,
          project_name: memex.name,
          project_kind: "MemexProject",
          performed_at: Time.now,
          public_project: false,
          actor: @other_user.login,
          actor_id: @other_user.id,
          org: @org.login,
          org_id: @org.id,
        }

        expected_hydro_message = serialize_message(
          project: memex,
          project_owner: memex.owner,
          actor: @other_user,
          action: :close,
          request_context: GitHub.context.to_hash
        )
        assert_hydro_published(expected_hydro_message, schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)

        assert event = events.pop, "an event was expected"
        assert_equal "project.close", event.name
        assert_equal expected_payload[:project_id], event.payload[:project_id]
        assert_equal expected_payload[:project_name], event.payload[:project_name]
        assert_equal expected_payload[:project_kind], event.payload[:project_kind]
        assert_equal expected_payload[:performed_at], event.payload[:performed_at]
        assert_equal expected_payload[:public_project], event.payload[:public_project]
        assert_equal expected_payload[:actor], event.payload[:actor]
        assert_equal expected_payload[:actor_id], event.payload[:actor_id]
        assert_equal expected_payload[:org_id], event.payload[:org_id]
        assert_equal expected_payload[:org], event.payload[:org]
      end
    end

    test "instruments project being made public", skip_with_all_emus: true do
      events = subscribe "project.visibility_public"
      now = DateTime.new(2021, 8, 10)

      Timecop.freeze(now) do
        memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org,
          public: false
        )

        memex.update!(public: true)

        expected_payload = {
          project_id: memex.id,
          project_name: memex.name,
          project_kind: "MemexProject",
          performed_at: Time.now,
          public_project: true,
          actor: @other_user.login,
          actor_id: @other_user.id,
          org_id: @org.id,
          org: @org.login,
        }

        assert event = events.pop, "an event was expected"
        assert_equal "project.visibility_public", event.name
        assert_equal expected_payload[:project_id], event.payload[:project_id]
        assert_equal expected_payload[:project_name], event.payload[:project_name]
        assert_equal expected_payload[:project_kind], event.payload[:project_kind]
        assert_equal expected_payload[:performed_at], event.payload[:performed_at]
        assert_equal expected_payload[:public_project], event.payload[:public_project]
        assert_equal expected_payload[:actor], event.payload[:actor]
        assert_equal expected_payload[:actor_id], event.payload[:actor_id]
        assert_equal expected_payload[:org_id], event.payload[:org_id]
        assert_equal expected_payload[:org], event.payload[:org]
      end
    end

    test "instruments project being made private", skip_with_all_emus: true do
      events = subscribe "project.visibility_private"
      now = DateTime.new(2021, 8, 10)

      Timecop.freeze(now) do
        memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org,
          public: true
        )

        memex.update(public: false)

        expected_payload = {
          project_id: memex.id,
          project_name: memex.name,
          project_kind: "MemexProject",
          performed_at: Time.now,
          public_project: false,
          actor: @other_user.login,
          actor_id: @other_user.id,
          org_id: @org.id,
          org: @org.login,
        }
        assert event = events.pop, "an event was expected"
        assert_equal "project.visibility_private", event.name
        assert_equal expected_payload[:project_id], event.payload[:project_id]
        assert_equal expected_payload[:project_name], event.payload[:project_name]
        assert_equal expected_payload[:project_kind], event.payload[:project_kind]
        assert_equal expected_payload[:performed_at], event.payload[:performed_at]
        assert_equal expected_payload[:public_project], event.payload[:public_project]
        assert_equal expected_payload[:actor], event.payload[:actor]
        assert_equal expected_payload[:actor_id], event.payload[:actor_id]
        assert_equal expected_payload[:org_id], event.payload[:org_id]
        assert_equal expected_payload[:org], event.payload[:org]
      end
    end

    test "instruments project being deleted" do
      events = subscribe "project.soft_delete"
      now = DateTime.new(2021, 8, 10)

      Timecop.freeze(now) do
        memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org,
        )

        memex.soft_delete!(@other_user)

        expected_payload = {
          project_id: memex.id,
          project_name: memex.name,
          project_kind: "MemexProject",
          performed_at: Time.now,
          public_project: false,
          actor: @other_user.login,
          actor_id: @other_user.id,
          org_id: @org.id,
          org: @org.login,
        }
        assert event = events.pop, "an event was expected"
        assert_equal "project.soft_delete", event.name
        assert_equal expected_payload[:project_id], event.payload[:project_id]
        assert_equal expected_payload[:project_name], event.payload[:project_name]
        assert_equal expected_payload[:project_kind], event.payload[:project_kind]
        assert_equal expected_payload[:performed_at], event.payload[:performed_at]
        assert_equal expected_payload[:public_project], event.payload[:public_project]
        assert_equal expected_payload[:actor], event.payload[:actor]
        assert_equal expected_payload[:actor_id], event.payload[:actor_id]
        assert_equal expected_payload[:org_id], event.payload[:org_id]
        assert_equal expected_payload[:org], event.payload[:org]
      end
    end

    test "publishes hydro messages when project is updated" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org
        )

        memex.update(title: "new title")

        expected_hydro_message = serialize_message(
          project: memex,
          project_owner: memex.owner,
          actor: @other_user,
          action: :update,
          request_context: GitHub.context.to_hash
        )
        assert_hydro_published(expected_hydro_message, schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)

        assert_hydro_published(serialize_user_generated_content_message({
          actor: @other_user,
          content_type: :MEMEX_PROJECT,
          content_database_id: memex.id,
          title: memex.title,
          content: "#{memex.short_description}\n#{memex.description}",
          owner: memex.owner
        }), ignore_extra_keys: true, schema: "github.platform_health.v1.UserGeneratedContent")
      end
    end

    test "publishes hydro message when project is re-opened" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        memex = create(
          :memex_project,
          title: "The Master Plan",
          description: "The way it will go down.",
          short_description: "tldr",
          creator: @user,
          owner: @org,
          closed_at: Time.now
        )

        memex.update(closed_at: nil)

        expected_hydro_message = serialize_message(
          project: memex,
          project_owner: memex.owner,
          actor: @other_user,
          action: :open,
          request_context: GitHub.context.to_hash
        )
        assert_hydro_published(expected_hydro_message, schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)
      end
    end

    test "publishes hydro message when project is destroyed" do
      memex = create(
        :memex_project,
        title: "The Master Plan",
        description: "The way it will go down.",
        short_description: "tldr",
        creator: @user,
        owner: @org
      )
      memex.destroy!

      expected_hydro_message = serialize_message(
        project: memex,
        project_owner: memex.owner,
        actor: @other_user,
        action: :delete,
        request_context: GitHub.context.to_hash
      )
      assert_hydro_published(expected_hydro_message, schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)
    end
  end

  context "multiple_associations support for prioritizes method" do
    context "memex_project_items" do
      context "prioritize_dependent" do
        test "correctly prioritizes dependents" do
          allow_transaction_nesting do
            memex = create(:memex_project, owner: @org, title: "My Memex Project")

            # Insert at top => [memex_item_one]
            memex_item_one = build(:memex_project_item, memex_project: memex, content: create(:issue))
            memex.prioritize_dependent!(memex_item_one, position: :top)
            memex.rebalance!(association: :memex_project_items, mode: GitHub::Prioritizable::Context::RebalanceMode::Dual)
            refute_nil memex_item_one.priority
            assert_equal(
              [memex_item_one.id],
              memex.reload.prioritized_scope(:memex_project_items).map(&:id)
            )

            # Insert at bottom => [memex_item_one, memex_item_two]
            memex_item_two = build(:memex_project_item, memex_project: memex, content: create(:issue))
            memex.prioritize_dependent!(memex_item_two, position: :bottom)
            memex.rebalance!(association: :memex_project_items, mode: GitHub::Prioritizable::Context::RebalanceMode::Dual)
            refute_nil memex_item_two.priority
            assert_equal(
              [memex_item_one.id, memex_item_two.id],
              memex.reload.prioritized_scope(:memex_project_items).map(&:id)
            )

            # Insert after => [memex_item_one, memex_item_two, memex_item_three]
            memex_item_three = build(:memex_project_item, memex_project: memex, content: create(:issue))
            memex.prioritize_dependent!(memex_item_three, after: memex_item_two.reload)
            memex.rebalance!(association: :memex_project_items, mode: GitHub::Prioritizable::Context::RebalanceMode::Dual)
            refute_nil memex_item_three.priority
            assert_equal(
              [memex_item_one.id, memex_item_two.id, memex_item_three.id],
              memex.reload.prioritized_scope(:memex_project_items).map(&:id)
            )

            # Insert before => [memex_item_three, memex_item_one, memex_item_two]
            memex.prioritize_dependent!(memex_item_three, before: memex_item_one.reload)
            memex.rebalance!(association: :memex_project_items, mode: GitHub::Prioritizable::Context::RebalanceMode::Dual)
            assert_equal(
              [memex_item_three.id, memex_item_one.id, memex_item_two.id],
              memex.reload.prioritized_scope(:memex_project_items).map(&:id)
            )
          end
        end

        test "raises `GitHub::Prioritizable::Context::LockedForRebalance` if context is currently locked for rebalance" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item_one = build(:memex_project_item, memex_project: memex, content: create(:issue))
          memex.lock_for_rebalance(association: :memex_project_items) do
            assert_raises GitHub::Prioritizable::Context::LockedForRebalance do
              memex.prioritize_dependent!(memex_item_one, position: :top)
            end
          end
        end

        test "traces its execution" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item = build(:memex_project_item, memex_project: memex, content: create(:issue))

          exporter.reset
          assert memex.prioritize_dependent!(memex_item, position: :top)

          memex.memex_project_items.reload
          span = find_span_by(name: "memex_project#prioritize_dependent!")

          refute_nil span
          assert_equal memex.id, span.attributes["context_id"]
          assert_equal memex.class.name, span.attributes["context_type"]
        end

        test "times its execution" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item = build(:memex_project_item, memex_project: memex, content: create(:issue))

          assert memex.prioritize_dependent!(memex_item, position: :top)

          assert_dogstats_distribution(
            1,
            "memex_project.prioritize_dependent.dist.time",
            tags: ["dual_write:false", "dependent:memex_project_item"]
          )
        end

        context "instruments dual writes" do
          test "when a new item is added to a project as part of prioritizable 'insert_at_top'" do
            memex = create(:memex_project, owner: @org, title: "Denormalized Project")
            memex_item = build(:memex_project_item, memex_project: memex, content: create(:issue))

            memex.prioritize_dependent!(
              memex_item,
              dual_write: memex.prioritize(
                item: memex_item,
                position: GitHub::Prioritizable::SBT::Position.from_options(position: :top),
                association: :memex_project_items,
              ),
            )

            assert_hydro_messages(count: 1, schema: "github.memex.v0.ProjectItemCreate")
          end

          test "when an item's priority changes as part of prioritizable 'insert_at_bottom'" do
            memex = create(:memex_project, owner: @org, title: "Denormalized Project")
            memex_item_one = build(:memex_project_item, memex_project: memex, content: create(:issue))

            memex_item_two = build(:memex_project_item, memex_project: memex, content: create(:issue))
            memex.prioritize_dependent!(
              memex_item_two,
              position: :bottom,
              dual_write: memex.prioritize(
                item: memex_item_two,
                position: GitHub::Prioritizable::SBT::Position.from_options(position: :bottom),
                association: :memex_project_items,
              ),
            )

            # publishes two events, for the new items in the project
            assert_hydro_messages(count: 1, schema: "github.memex.v0.ProjectItemCreate")
          end

          test "instruments dual writes when an item's priority changes as part of prioritizable 'change_priority'" do
            memex = create(:memex_project, owner: @org, title: "Denormalized Project")
            memex_item_one = build(:memex_project_item, memex_project: memex, content: create(:issue))

            # Insert at top => [memex_item_one]
            memex.prioritize_dependent!(
              memex_item_one,
              position: :top,
              dual_write: memex.prioritize(
                item: memex_item_one,
                position: GitHub::Prioritizable::SBT::Position.from_options(position: :top),
                association: :memex_project_items,
              ),
            )

            # Insert at bottom => [memex_item_one, memex_item_two]
            memex_item_two = build(:memex_project_item, memex_project: memex, content: create(:issue))
            memex.prioritize_dependent!(
              memex_item_two,
              position: :bottom,
              dual_write: memex.prioritize(
                item: memex_item_two,
                position: GitHub::Prioritizable::SBT::Position.from_options(position: :bottom),
                association: :memex_project_items,
              ),
            )

            # publishes two events, for the new items in the project
            assert_hydro_messages(count: 2, schema: "github.memex.v0.ProjectItemCreate")

            # Insert before => [memex_item_two, memex_item_one]
            memex.prioritize_dependent!(
              memex_item_two,
              before: memex_item_one.reload,
              dual_write: memex.prioritize(
                item: memex_item_two,
                position: GitHub::Prioritizable::SBT::Position.from_options({ before: memex_item_one }),
                association: :memex_project_items,
              ),
            )

            # publishes one event, for moving memex_item_two before memex_item_one
            assert_hydro_messages(count: 1, schema: "github.memex.v0.ProjectItemUpdate")
          end
        end
      end

      context "prioritize!" do
        test "traces its execution" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item = build(:memex_project_item, memex_project: memex, content: create(:issue))

          exporter.reset
          assert memex.prioritize!(
            item: memex_item,
            association: :memex_project_items,
            position: GitHub::Prioritizable::SBT::Position::Top.new
          )

          span = find_span_by(name: "memex_project#prioritize!")

          refute_nil span
          assert_equal "MemexProject", span.attributes["context"]
          assert_equal "memex_project_items", span.attributes["association"]
          assert_equal "top", span.attributes["position"]
        end

        test "times its execution" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item = build(:memex_project_item, memex_project: memex, content: create(:issue))

          assert memex.prioritize!(
            item: memex_item,
            association: :memex_project_items,
            position: GitHub::Prioritizable::SBT::Position::Top.new
          )

          assert_dogstats_distribution(
            1,
            "github.prioritizable.sbt.context.prioritize-bang",
            tags: ["context:MemexProject", "association:memex_project_items", "position:top"]
          )
        end

        test "instruments an item's priority on item create" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item = build(:memex_project_item, memex_project: memex, content: create(:issue))

          assert memex.prioritize!(
            item: memex_item,
            association: :memex_project_items,
            position: GitHub::Prioritizable::SBT::Position::Top.new
          )

          assert_hydro_messages(count: 1, schema: "github.memex.v0.ProjectItemCreate")
          assert_hydro_messages(count: 0, schema: "github.memex.v0.ProjectItemMetadataUpdate")
        end

        test "instruments an item's priority when an item's priority changes" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item_one = build(:memex_project_item, memex_project: memex, content: create(:issue, title: "item 1"))

          assert memex.prioritize!(
            item: memex_item_one,
            association: :memex_project_items,
            position: GitHub::Prioritizable::SBT::Position::Top.new
          )

          memex_item_two = build(:memex_project_item, memex_project: memex, content: create(:issue, title: "item 2"))
          assert memex.prioritize!(
            item: memex_item_two,
            association: :memex_project_items,
            position: GitHub::Prioritizable::SBT::Position::Top.new
          )

          assert_hydro_messages(count: 2, schema: "github.memex.v0.ProjectItemCreate")

          assert memex.prioritize!(
            item: memex_item_two,
            association: :memex_project_items,
            position: GitHub::Prioritizable::SBT::Position::LowerThan.new(memex_item_one)
          )

          assert_hydro_messages(count: 1, schema: "github.memex.v0.ProjectItemUpdate")
          assert_hydro_messages(count: 1, schema: "github.memex.v0.ProjectItemMetadataUpdate")
        end
      end

      context "prioritize" do
        test "traces its execution" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item = build(:memex_project_item, memex_project: memex, content: create(:issue))

          exporter.reset
          assert memex.prioritize(
            item: memex_item,
            association: :memex_project_items,
            position: GitHub::Prioritizable::SBT::Position::Top.new
          )

          span = find_span_by(name: "memex_project#prioritize")

          refute_nil span
          assert_equal "MemexProject", span.attributes["context"]
          assert_equal "memex_project_items", span.attributes["association"]
          assert_equal "top", span.attributes["position"]
        end

        test "times its execution" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          memex_item = build(:memex_project_item, memex_project: memex, content: create(:issue))

          assert memex.prioritize(
            item: memex_item,
            association: :memex_project_items,
            position: GitHub::Prioritizable::SBT::Position::Top.new
          )

          assert_dogstats_distribution(
            1,
            "github.prioritizable.sbt.context.prioritize",
            tags: ["context:MemexProject", "association:memex_project_items", "position:top"]
          )
        end
      end

      test "deprioritize dependent works correctly" do
        memex = create(:memex_project, owner: @org, title: "My Memex Project")

        # Create and prioritize an item
        memex_item_one = build(:memex_project_item, memex_project: memex, content: create(:issue))
        memex.prioritize_dependent!(memex_item_one, position: :top)
        refute_nil memex_item_one.priority

        memex.deprioritize_dependent(memex_item_one)
        assert_empty memex.memex_project_items.where(id: memex_item_one.id)
      end

      context "prioritized?" do
        test "returns true if all items have a priority" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")

          # Create and prioritize an item
          memex_item_one = build(:memex_project_item, memex_project: memex, content: create(:issue))
          memex.prioritize_dependent!(memex_item_one, position: :top)
          refute_nil memex_item_one.priority

          assert memex.prioritized?(association: :memex_project_items)
        end

        test "raises `InvalidAssociation` if unsupported association is passed" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          assert_raises GitHub::Prioritizable::Context::InvalidAssociation do
            memex.prioritized?(association: :memex_project_columns)
          end
        end
      end

      context "prioritizable?" do
        test "returns true if the number of prioritized items < the max allowed items" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")

          # Create and prioritize an item
          memex_item_one = build(:memex_project_item, memex_project: memex, content: create(:issue))
          memex.prioritize_dependent!(memex_item_one, position: :top)

          assert memex.prioritizable?(association: :memex_project_items)
        end

        test "raises `InvalidAssociation` if unsupported association is passed" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          assert_raises GitHub::Prioritizable::Context::InvalidAssociation do
            memex.prioritizable?(association: :memex_project_columns)
          end
        end
      end

      context "rebalance!" do
        test "raises `InvalidAssociation` if unsupported association is passed" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          assert_raises GitHub::Prioritizable::Context::InvalidAssociation do
            memex.rebalance!(association: :memex_project_columns)
          end
        end

        test "rebalances the project using the `virtual_priority` column rather than the legacy `priority` column" do
          memex_project = create(:memex_project, owner: @org)
          items = (1..10).map do |n|
            create(:memex_project_item, memex_project:, priority: nil, priority_numerator: n * 100, priority_denominator: 1)
          end
          expected_order = items.reverse.to_a

          assert_equal expected_order.map(&:id), memex_project.prioritized_scope(:memex_project_items).map(&:id)

          # Reload the project before and after rebalance in order to fetch the generated `virtual_priority` column
          # from the database afresh in both instances.
          memex_project.reload
          memex_project.rebalance!(association: :memex_project_items)
          memex_project.reload

          # We should have skipped updating the legacy column altogether.
          assert memex_project.memex_project_items.none?(&:priority)

          # We should have rebalanced all the values in the `virtual_priority` column.
          assert_same_elements(
            ["19/2", "17/2", "15/2", "13/2", "11/2", "9/2", "7/2", "5/2", "3/2", "1/2"].map(&:to_r),
            memex_project.memex_project_items.map(&:virtual_priority)
          )

          # We should have maintained the original order of items despite having rebalanced the underlying values.
          assert_equal expected_order.map(&:id), memex_project.prioritized_scope(:memex_project_items).map(&:id)
        end
      end

      test "locked_for_rebalance - raises `InvalidAssociation` if unsupported association is passed" do
        memex = create(:memex_project, owner: @org, title: "My Memex Project")
        assert_raises GitHub::Prioritizable::Context::InvalidAssociation do
          memex.locked_for_rebalance?(association: :memex_project_columns)
        end
      end

      context "rebalance" do
        test "Enqueues the rebalance_job_class and runs it if it is configured and there are no other jobs in the queue" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          user = create(:verified_user)
          memex_item_one = create(:memex_project_item, memex_project: memex, content: create(:issue))
          memex_item_two = create(:memex_project_item, memex_project: memex, content: create(:issue))

          assert_enqueued_jobs 1 do
            memex.rebalance(association: :memex_project_items)
          end
        end
        test "raises `InvalidAssociation` if unsupported association is passed" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          assert_raises GitHub::Prioritizable::Context::InvalidAssociation do
            memex.rebalance(association: :memex_project_columns)
          end
        end
      end

      test "memex_project exposes a prioritized_scope(:memex_project_items) field" do
        memex = MemexProject.create_with_associations(
          owner: @org,
          creator: @user,
          title: "My Memex Project"
        )
        memex_item_one = create(:memex_project_item, memex_project: memex, content: create(:issue))

        refute_nil memex.prioritized_scope(:memex_project_items)
        assert_equal memex.prioritized_scope(:memex_project_items)[0].class.name, "MemexProjectItem"
      end

      test "triggers an async rebalance before a MovedTooFar error is thrown" do
        memex = create(:memex_project, owner: @org, title: "My Memex Project")
        memex_item_one = create(:memex_project_item, memex_project: memex, content: create(:issue))
        memex_item_one.update!(priority: 1, priority_numerator: 1, priority_denominator: 1)
        memex_item_two = create(:memex_project_item, memex_project: memex, content: create(:issue))
        memex_item_two.update!(priority: 2, priority_numerator: 2, priority_denominator: 1)

        # Prioritized items: [item2, item1]
        assert_equal(
          [memex_item_two.id, memex_item_one.id],
          memex.reload.prioritized_scope(:memex_project_items).map(&:id)
        )
        memex_item_three = build(:memex_project_item, memex_project: memex, content: create(:issue))

        allow_transaction_nesting do
          # Simulate MAX_MOVES=0
          simulate_no_max_moves do
            assert_enqueued_jobs 1, only: RebalanceMemexProjectJob do
              assert_raises(GitHub::Prioritizable::RebalanceRequiredError) do
                # [item2, item1]
                # For item3 to be inserted after item2, item1 needs to be shifted by 1
                # Since this is greater than the simulated max moves of 0,
                # it will throw MovedTooFar error and also trigger an async rebalance
                memex.prioritize_dependent!(memex_item_three, after: memex_item_two)
              end
            end
          end
        end
      end
    end

    context "memex_project_views" do
      context "prioritize_dependent!" do
        test "times its execution" do
          memex = create(:memex_project, owner: @org, title: "My Memex Project")
          view = build(:memex_project_view, memex_project: memex)
          GitHub.dogstats.reset

          assert memex.prioritize_dependent!(view, position: :top)

          assert_dogstats_distribution(
            1,
            "memex_project.prioritize_dependent.dist.time",
            tags: ["dual_write:false", "dependent:memex_project_view"]
          )
        end
      end
    end
  end

  context "#collaborators" do
    test "returns a list of collaborators" do
      users = 5.times do
        create(:verified_user).tap do |user|
          @user_memex.grant_role(user, Role.project_reader_role)
          user
        end
      end

      admin = @org.admins.first

      collaborators, queries = log_cleaned_queries do
        @user_memex.collaborators(admin)
      end

      assert_equal queries.count, 4
      assert_equal collaborators.count, 5
    end
  end

  context "blocked user" do
    test "blocked user cannot access user-owned private project" do
      @user_memex.grant_role(@non_member, Role.project_writer_role)
      assert @user_memex.viewer_can_write?(@non_member)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @user.block(@non_member)
      end

      refute @user_memex.viewer_can_write?(@non_member)
      refute @user_memex.viewer_can_read?(@non_member)
    end

    test "blocked user can access user-owner public project as readonly" do
      @user_public_memex.grant_role(@non_member, Role.project_writer_role)
      assert @user_public_memex.viewer_can_write?(@non_member)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @user.block(@non_member)
      end

      refute @user_public_memex.viewer_can_write?(@non_member)
      assert @user_public_memex.viewer_can_read?(@non_member)
    end

    test "after unblocking, the previously blocked user has no access to the user-owned private project" do
      @user_memex.grant_role(@non_member, Role.project_writer_role)
      assert @user_memex.viewer_can_write?(@non_member)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @user.block(@non_member)
      end

      refute @user_memex.viewer_can_write?(@non_member)
      refute @user_memex.viewer_can_read?(@non_member)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @user.unblock(@non_member)
      end

      refute @user_memex.viewer_can_write?(@non_member)
      refute @user_memex.viewer_can_read?(@non_member)
    end

    test "after unblocking, the previously blocked user has readonly access to the user-owned public project" do
      @user_public_memex.grant_role(@non_member, Role.project_writer_role)
      assert @user_public_memex.viewer_can_write?(@non_member)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @user.block(@non_member)
      end

      refute @user_public_memex.viewer_can_write?(@non_member)
      assert @user_public_memex.viewer_can_read?(@non_member)

      perform_enqueued_jobs(only: [IgnoreUserJob]) do
        @user.unblock(@non_member)
      end

      refute @user_public_memex.viewer_can_write?(@non_member)
      assert @user_public_memex.viewer_can_read?(@non_member)
    end

    # These tests check if the authzd policies are working correctly.
    # When the IgnoreUserJob fails (in this test we just stub it out),
    # then the blocked user is not removed as a collbaorator from the project.
    # However, the authzd policies should:
    #   prevent the blocked user from accessing the project if it is a private project
    #   grant readonly access if the project is public
    context "Memex Project Authzd policies" do
      test "prevent a blocked user from accessing a user-owned private project" do
        member2 = create(:verified_user)

        @user_memex.grant_role(@non_member, Role.project_writer_role)
        @user_memex.grant_role(member2, Role.project_writer_role)
        assert @user_memex.viewer_can_write?(@non_member)
        assert @user_memex.viewer_can_write?(member2)

        # Stub the perform method so the job doesn't do anything
        IgnoreUserJob.any_instance.stubs(:perform)
        perform_enqueued_jobs(only: [IgnoreUserJob]) do
          @user.block(@non_member)
        end

        # member2 still has correct access
        assert @user_memex.viewer_can_write?(member2)

        # @non_member gets blocked
        refute @user_memex.viewer_can_write?(@non_member)
        refute @user_memex.viewer_can_read?(@non_member)
      end

      test "grant a blocked user readonly access to a user-owned public project" do
        member2 = create(:verified_user)

        @user_public_memex.grant_role(@non_member, Role.project_writer_role)
        @user_public_memex.grant_role(member2, Role.project_writer_role)
        assert @user_public_memex.viewer_can_write?(@non_member)
        assert @user_public_memex.viewer_can_write?(member2)

        # Stub the perform method so the job doesn't do anything
        IgnoreUserJob.any_instance.stubs(:perform)
        perform_enqueued_jobs(only: [IgnoreUserJob]) do
          @user.block(@non_member)
        end

        # member2 still has correct access
        assert @user_public_memex.viewer_can_write?(member2)

        # @non_member gets readonly access
        assert @user_public_memex.viewer_can_read?(@non_member)
        refute @user_public_memex.viewer_can_write?(@non_member)
      end
    end
  end

  context "soft_delete" do
    test "updates deleted fields for user memex" do
      @user_memex.soft_delete!(@other_user)
      @user_memex.reload

      assert @user_memex.deleted_at.is_a?(Time)
      assert_equal @user_memex.deleted_by_id, @other_user.id

      assert_hydro_published(serialize_message(
        project: @user_memex,
        project_owner: @user_memex.owner,
        actor: @other_user,
        action: :soft_delete,
        request_context: GitHub.context.to_hash
      ), schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)
      refute hydro_messages(schema: "github.memex.v0.MemexProjectEvent").any? { |m| m["action"] == "update" }
    end

    test "updates deleted fields for org memex" do
      @org_memex.soft_delete!(@other_user)
      @org_memex.reload

      assert @org_memex.deleted_at.is_a?(Time)
      assert_equal @org_memex.deleted_by_id, @other_user.id

      assert_hydro_published(serialize_message(
        project: @org_memex,
        project_owner: @org_memex.owner,
        actor: @other_user,
        action: :soft_delete,
        request_context: GitHub.context.to_hash
      ), schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)
      refute hydro_messages(schema: "github.memex.v0.MemexProjectEvent").any? { |m| m["action"] == "update" }
    end

    test "disables workflows associated with a memex" do
      memex = create(:memex_project)
      workflows = [
        MemexProjectWorkflow.default_closed_workflow_attributes(
          status_column: memex.status_column,
          creator: memex.creator,
          enabled: true
        )
      ]
      memex.workflows.create(workflows)
      assert memex.workflows.first.enabled

      memex.soft_delete!(@other_user)
      memex.reload

      refute memex.workflows.first.enabled
    end

    test "enqueues a job to synchronize content search indexes" do
      memex = create(:memex_project)

      MemexProjectReindexContentJob.expects(:perform_later).once.with(memex.id)
      memex.soft_delete!(@other_user)
    end
  end

  context "restore" do
    test "removes deleted status for user memex" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        @user_memex.soft_delete!(@other_user)
        @user_memex.reload

        assert @user_memex.deleted?

        @user_memex.restore!
        @user_memex.reload

        refute @user_memex.deleted?

        assert_hydro_published(serialize_message(
          project: @user_memex,
          project_owner: @user_memex.owner,
          actor: @other_user,
          action: :restore,
          request_context: GitHub.context.to_hash
        ), schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)
        refute hydro_messages(schema: "github.memex.v0.MemexProjectEvent").any? { |m| m["action"] == "update" }
      end
    end

    test "removes deleted status for org memex" do
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        @org_memex.soft_delete!(@other_user)
        @org_memex.reload

        assert @org_memex.deleted?

        @org_memex.restore!
        @org_memex.reload

        refute @org_memex.deleted?

        assert_hydro_published(serialize_message(
          project: @org_memex,
          project_owner: @org_memex.owner,
          actor: @other_user,
          action: :restore,
          request_context: GitHub.context.to_hash
        ), schema: "github.memex.v0.MemexProjectEvent", topic: "github.memex.v0.MemexProjectEvent", count: 1)
        refute hydro_messages(schema: "github.memex.v0.MemexProjectEvent").any? { |m| m["action"] == "update" }
      end
    end

    test "enqueues a job to synchronize content search indexes" do
      memex = create(:memex_project, deleted_at: Time.now)

      MemexProjectReindexContentJob.expects(:perform_later).once.with(memex.id)
      memex.restore!
    end
  end

  context "#transform_owner_type!" do
    test "sets the correct owner type" do
      memex = create(:memex_project, owner: @user)

      memex.transform_owner_type!(new_owner: @org, new_creator: @user)
      memex.reload

      assert_equal @org, memex.owner
      assert_equal "Organization", memex.owner_type
    end

    test "individual collaborators do not lose access" do
      memex = create(:memex_project, owner: @user)
      collab = create(:user)

      memex.grant_role(collab, Role.project_writer_role)

      memex.transform_owner_type!(new_owner: @org, new_creator: @user)
      memex.reload

      assert memex.viewer_can_write?(collab)
    end

    test "changes the creator" do
      memex = create(:memex_project, owner: @user, creator: @user)
      creator = create(:verified_user)

      memex.transform_owner_type!(new_owner: @org, new_creator: creator)
      memex.reload

      assert_equal creator, memex.creator
    end

    test "updates the project number" do
      memex = create(:memex_project, owner: @user, creator: @user)
      creator = create(:verified_user)

      # updates number before transformation to non-existing value
      memex.number = nil
      memex.set_number
      memex.save!

      old_number = memex.number

      memex.transform_owner_type!(new_owner: @org, new_creator: creator)
      memex.reload

      refute_equal old_number, memex.number
    end

    test "raises an error with a new owner that's a user" do
      memex = create(:memex_project, owner: @org)

      assert_raises "Cannot transform Organization memex_project to User memex_project" do
        memex.transform_owner_type!(owner: @owner, new_creator: @owner)
      end
    end
  end

  context "partition_items_by_readability" do
    test "returns empty arrays if no ids passed" do
      memex = create(:memex_project, owner: @org)
      public_issue_item = create(:memex_project_item, memex_project: memex, content: @issue)
      private_issue_item = create(:memex_project_item, memex_project: memex, content: @private_issue)

      draft_item = build(:memex_project_item, memex_project: memex, priority: 1)
      draft_item.content = draft_item.build_draft_issue(title: Faker::Lorem.unique.word)
      draft_item.save!

      viewable_items, unviewable_items = memex.partition_items_by_readability(@user, [])

      assert_empty viewable_items
      assert_empty unviewable_items
    end

    test "returns viewable item and unviewable items in separate arrays and ids not passed are not included" do
      memex = create(:memex_project, owner: @org)
      public_issue_item = create(:memex_project_item, memex_project: memex, content: @issue)
      private_issue_item = create(:memex_project_item, memex_project: memex, content: @private_issue)

      draft_item = build(:memex_project_item, memex_project: memex, priority: 1)
      draft_item.content = draft_item.build_draft_issue(title: Faker::Lorem.unique.word)
      draft_item.save!

      viewable_items, unviewable_items = memex.partition_items_by_readability(@user, [public_issue_item.id, private_issue_item.id])

      assert_equal 1, viewable_items.size
      assert_equal public_issue_item, viewable_items.first
      assert_equal 1, unviewable_items.size
      assert_equal private_issue_item, unviewable_items.first
    end
  end

  context "#destroy_template_project_links" do
    test "destroys associated memex_project_links for a memex project template when project is closed" do
      memex = create(
        :memex_project,
        title: "The Master Plan",
        description: "The way it will go down.",
        short_description: "tldr",
        creator: @user,
        owner: @org,
        public: false
      )

      memex_template = create(:memex_template, memex_project: memex)

      memex_project_link = create(:memex_project_link, source_type: "Organization", source_id: @org.id, memex_project: memex)

      assert MemexProjectLink.find_by(id: memex_project_link.id)

      assert_difference "MemexProjectLink.count", -1 do
        now = DateTime.new(2021, 05, 06)
        memex.update!(closed_at: now)
      end

      assert_nil MemexProjectLink.find_by(id: memex_project_link.id)
    end
  end

  context "#find_column_by_name_or_id" do
    test "returns column when passing in an id" do
      column = create(:single_select_memex_column, memex_project: @org_memex)
      assert_equal column, @org_memex.reload.find_column_by_name_or_id(column.id)
    end

    test "returns column when passing system defined column id" do
      column = @org_memex.columns.find(&:title?)
      assert_equal column, @org_memex.find_column_by_name_or_id(column.synthetic_id)
    end

    test "returns column when passing system defined column id regardless of case" do
      column = @org_memex.columns.find(&:linked_pull_requests?)
      assert_equal column, @org_memex.find_column_by_name_or_id("LinKED PulL ReQUESTS") # derp
    end
  end

  context "#last_visited_on" do
    test "new projects do not have a last_visited_on" do
      memex_project = create(:memex_project)

      assert_nil memex_project.last_visited_on, "Expected the project to not have been visited"
    end
  end

  context "#update_last_visited_on" do
    test "can update last_visited_on" do
      travel_to Time.new(2020, 1, 1) do
        memex_project = create(:memex_project)

        assert_changes -> { memex_project.last_visited_on }, from: nil, to: Date.new(2020, 1, 1) do
          memex_project.update_last_visited_on
        end
      end
    end

    test "updates last_visited_on on a new day" do
      travel_to Time.new(2020, 1, 1) do
        memex_project = create(:memex_project)

        assert_changes -> { memex_project.last_visited_on }, from: nil, to: Date.new(2020, 1, 1) do
          assert memex_project.update_last_visited_on, "Expected to update last visited timestamp"
        end

        memex_project.reload

        travel 1.day

        assert_changes -> { memex_project.last_visited_on }, from: Date.new(2020, 1, 1), to: Date.new(2020, 1, 2) do
          assert memex_project.update_last_visited_on, "Expected to update last visited timestamp"
        end
      end
    end

    test "does not update last_visited_on when it has already been updated for a given day" do
      travel_to Time.new(2020, 1, 1) do
        memex_project = create(:memex_project)

        assert_changes -> { memex_project.last_visited_on }, from: nil, to: Date.new(2020, 1, 1) do
          assert memex_project.update_last_visited_on, "Expected to update last visited timestamp"
        end

        memex_project.reload

        assert_no_changes -> { memex_project.last_visited_on }, from: Date.new(2020, 1, 1) do
          refute memex_project.update_last_visited_on, "Expected to not update last visited timestamp"
        end
      end
    end
  end

  context "#update_last_visited_at_for_viewer" do
    test "adds a new MemexProjectVisit for a viewer when none exists" do
      memex = create(:memex_project)
      viewer = create(:verified_user)

      refute memex.memex_project_visits.find_by(viewer_id: viewer.id)
      now = DateTime.new(2021, 05, 06)
      Timecop.freeze(now) do
        memex.update_last_visited_at_for_viewer(viewer: viewer)
      end

      visit = memex.memex_project_visits.find_by(viewer_id: viewer.id)
      assert visit
      assert_equal visit.last_visited_at, now
    end

    test "updates the timestamp of a MemexProjectVisit for a viewer when a previous entry exists" do
      memex = create(:memex_project)
      viewer = create(:verified_user)
      now = DateTime.new(2021, 05, 06)

      Timecop.freeze(now) do
        memex.update_last_visited_at_for_viewer(viewer: viewer)

        assert_equal memex.memex_project_visits.find_by(viewer_id: viewer.id).last_visited_at, now
      end

      later = DateTime.new(2022, 05, 06)

      Timecop.freeze(later) do
        memex.update_last_visited_at_for_viewer(viewer: viewer)

        assert_equal memex.memex_project_visits.find_by(viewer_id: viewer.id).last_visited_at, later
      end
    end

    test "updates the last_visited_on timestamp" do
      memex_project = create(:memex_project)
      viewer = create(:verified_user)

      travel_to Time.new(2020, 1, 1) do
        assert_changes -> { memex_project.last_visited_on }, from: nil, to: Date.new(2020, 1, 1) do
          memex_project.update_last_visited_at_for_viewer(viewer: viewer)
        end
      end
    end
  end

  context "#queue_reindex_items" do
    test "queues the resync job and returns a job status" do
      # Stub out this method so that we continue to enqueue the job even if `queue_reindex_items` is called multiple
      # times in quick succession. Without this stub, this test will fail in the gauntlet run.
      # Because the test here is mainly concerned with the job being enqueued when `queue_reindex_items` is called, not
      # with the rate limiting behavior, we are good to stub this out.
      RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)

      assert_enqueued_with(job: ResyncMemexProjectItemsIndexJob) do
        status = @org_memex.queue_reindex_items
        assert status.is_a?(JobStatus)
        assert_predicate status, :pending?
      end
    end
  end

  context "#memex_without_limits_alpha_projects" do
    test "does not return any projects if FFs are not enabled" do
      assert_empty MemexProject.memex_without_limits_beta_projects
    end

    test "returns a project id with the memex_paginated_archive FF enabled" do
      GitHub.flipper[:memex_paginated_archive].enable(@org_memex)

      projects = MemexProject.memex_without_limits_beta_projects

      assert_equal projects.length, 1
      assert_equal projects[0], @org_memex.id
    end

    test "returns a project id with the memex_table_without_limits FF enabled" do
      GitHub.flipper[:memex_table_without_limits].enable(@org_memex)

      projects = MemexProject.memex_without_limits_beta_projects

      assert_equal projects.length, 1
      assert_equal projects[0], @org_memex.id
    end

    test "de-duplicates project ids in both FFs" do
      GitHub.flipper[:memex_paginated_archive].enable(@org_memex)
      GitHub.flipper[:memex_table_without_limits].enable(@org_memex)
      GitHub.flipper[:memex_table_without_limits].enable(@user_memex)

      projects = MemexProject.memex_without_limits_beta_projects

      assert_equal projects.length, 2
      assert_equal projects[0], @org_memex.id
      assert_equal projects[1], @user_memex.id
    end
  end

  context "#items_limit" do
    test "returns the default limit if the project is not in the memex_table_without_limits feature flag" do
      GitHub.flipper[:memex_table_without_limits].disable(@org_memex)
      assert_equal MemexProjectItem::PER_PAGE_LIMIT, @org_memex.items_limit
    end

    test "returns the Memex Without Limit items limit if the project is in the memex_table_without_limits feature flag" do
      GitHub.flipper[:memex_table_without_limits].enable(@org_memex)
      assert_equal MemexProjectItem::EXPANDED_ITEM_LIMIT, @org_memex.items_limit
    end

    test "returns the default limit if the project is in the memex_table_without_limits feature flag but the kill switch is enabled" do
      GitHub.flipper[:memex_table_without_limits].enable(@org_memex)
      GitHub.flipper[:memex_without_limits_kill_switch].enable
      assert_equal MemexProjectItem::PER_PAGE_LIMIT, @org_memex.items_limit
    end
  end

  context "#flipper_actor_names" do
    test "from_flipper_actor_name" do
      org = create(:organization)
      user = create(:verified_user)

      org_project = create(:memex_project, owner: org)
      user_project = create(:memex_project, owner: user)

      # assert that getting the MemexProject from the flipper actor name returns the same MemexProject
      assert_equal org_project, MemexProject.from_flipper_actor_name(org_project.flipper_actor_name)
      assert_equal user_project, MemexProject.from_flipper_actor_name(user_project.flipper_actor_name)

      # assert that the flipper actor name has been overridden and is not the same as the flipper id
      refute_equal org_project.flipper_id, org_project.flipper_actor_name
      refute_equal user_project.flipper_id, user_project.flipper_actor_name

      # assert that that flipper actor name is in the expected format
      assert_equal  "#{org_project.owner_type}/#{org_project.search_slug}", org_project.flipper_actor_name
      assert_equal  "#{user_project.owner_type}/#{user_project.search_slug}", user_project.flipper_actor_name
    end
  end

  context "#permalink" do
    test "includes host by default" do
      organization = create(:organization)
      memex_project = create(:memex_project, owner: organization)

      assert_predicate memex_project, :org_owned?
      assert_equal "https://github.com/orgs/#{organization.display_login}/projects/#{memex_project.number}", memex_project.permalink
    end

    test "can return path" do
      organization = create(:organization)
      memex_project = create(:memex_project, owner: organization)

      assert_equal "/orgs/#{organization.display_login}/projects/#{memex_project.number}", memex_project.permalink(include_host: false)
    end

    test "returns the permalink for organization owned projects" do
      organization = create(:organization)
      memex_project = create(:memex_project, owner: organization)

      assert_predicate memex_project, :org_owned?
      assert_equal "https://github.com/orgs/#{organization.display_login}/projects/#{memex_project.number}", memex_project.permalink
    end

    test "returns the permalink for user owned projects" do
      user = create(:verified_user)
      memex_project = create(:memex_project, owner: user)

      assert_predicate memex_project, :user_owned?
      assert_equal "https://github.com/users/#{user.display_login}/projects/#{memex_project.number}", memex_project.permalink
    end
  end

  test "list_id generates unique List-ID header" do
    user = create(:verified_user, login: "my-user")
    memex_project = create(:memex_project, owner: user, title: "My Memex")

    assert_equal "My Memex <1.projects.my-user.github.com>", memex_project.list_id
  end

  context "notification adapters" do
    test "returns self for notifications_thread" do
      memex_project = create(:memex_project)

      assert_equal memex_project, memex_project.notifications_thread
    end
  end

  context "#resolve_tenant" do
    test "resolves to the parent business for an organization owner", skip_enterprise: true do
      business_admin = create(:emu)
      business = business_admin.enterprise_managed_business
      business_org = create(:organization, business:)
      business_org_owned_project = create(:memex_project, owner: business_org)

      assert_equal business, business_org_owned_project.resolve_tenant
    end

    test "resolves to the parent business for a admin emu owner", skip_enterprise: true do
      GitHub.flipper[:memex_resolve_tenant].enable
      business_admin = create(:emu)
      business = business_admin.enterprise_managed_business
      admin_emu_owned_project = create(:memex_project, owner: business_admin)

      assert_equal business, admin_emu_owned_project.resolve_tenant
    end

    test "resolves to the parent business for a non-admin emu owner", skip_enterprise: true do
      GitHub.flipper[:memex_resolve_tenant].enable
      business_admin = create(:emu)
      business = business_admin.enterprise_managed_business
      emu2 = create(:emu, business: business)
      non_admin_emu_owned_project = create(:memex_project, owner: emu2)
      assert_equal business, non_admin_emu_owned_project.resolve_tenant
    end

    test "resolves to nil for emu owner when :memex_resolve_tenant is disabled", skip_enterprise: true do
      GitHub.flipper[:memex_resolve_tenant].disable
      business_admin = create(:emu)
      business = business_admin.enterprise_managed_business
      admin_emu_owned_project = create(:memex_project, owner: business_admin)

      assert_nil admin_emu_owned_project.resolve_tenant
    end

    test "resolves to nil for an organization owner that is not part of a business" do
      org = create(:organization)
      org_owned_project = create(:memex_project, owner: org)

      assert_nil org_owned_project.resolve_tenant
    end

    test "resolves to nil for a user owner" do
      user = create(:user)
      user_owned_project = create(:memex_project, owner: user)

      assert_nil user_owned_project.resolve_tenant
    end
  end

  context "#private_asset_url" do
    test "returns new-style url when use_new_url is true" do
      assert_equal "#{GitHub.url}/user-attachments/assets/fake-guid", @org_memex.private_asset_url(123, "fake-guid", true)
      assert_equal "#{GitHub.url}/user-attachments/assets/fake-guid", @user_memex.private_asset_url(123, "fake-guid", true)
    end

    test "returns old-style url when use_new_url is false" do
      assert_equal "#{GitHub.url}#{@org_memex.url}/assets/123/fake-guid", @org_memex.private_asset_url(123, "fake-guid", false)
      assert_equal "#{GitHub.url}#{@user_memex.url}/assets/123/fake-guid", @user_memex.private_asset_url(123, "fake-guid", false)
    end
  end

  context "#unlimited_charts?" do
    test "enterprise plans have unlimited charts", enterprise_only: true do
      paid_org = create(:organization, plan: "enterprise")
      private_project = create(:memex_project, owner: paid_org, public: false)

      assert private_project.unlimited_charts?
    end
  end

  context "#insights_enabled_for_owner" do
    test "enterprise plans have insights enabled", enterprise_only: true do
      paid_org = create(:organization, plan: "enterprise")
      private_project = create(:memex_project, owner: paid_org, public: false)

      assert private_project.insights_enabled_for_owner?
    end
  end
end
