# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include StringFromBinaryTestHelper
  include DogstatsTestHelpers
  include BackgroundDeletesTestHelpers

  fixtures do

    @owner = create(:user)
    @admin = create(:verified_user)

    @org = create(:organization, plan: "silver").tap do |o|
      o.add_member(@owner, action: :admin)
    end

    @repo = create(:private_repository, owner: @org)
  end

  setup do
    GitHub.context.push(actor_id: @owner.id)
  end

  context ".open_projects" do
    test "only includes open projects" do
      open_project = create(:project, closed_at: nil)
      create(:project, closed_at: Time.now)
      create(:project, deleted_at: Time.now)

      assert_same_elements [open_project], Project.open_projects
    end
  end

  context ".closed_projects" do
    test "only includes closed projects" do
      closed_project = create(:project, closed_at: Time.now)
      create(:project, closed_at: nil)
      create(:project, closed_at: Time.now, deleted_at: Time.now)

      assert_same_elements [closed_project], Project.closed_projects
    end
  end

  context ".public_projects" do
    test "only includes public projects" do
      public_project = create(:project, public: true)
      create_pair(:project, public: false)

      assert_same_elements [public_project], Project.public_projects
    end
  end

  context ".owner_projects_enabled" do
    test "includes project when owning repo has repo projects enabled" do
      @repo.enable_repository_projects(actor: @owner)
      project = create(:project, owner: @repo)

      assert_includes Project.owner_projects_enabled, project
    end

    test "excludes project when owning repo has repo projects disabled" do
      # disable after creating project to ensure model validation passes
      project = create(:project, owner: @repo)
      @repo.disable_repository_projects(actor: @owner)
      refute_includes Project.owner_projects_enabled, project
    end

    test "includes project when owning org has org projects enabled" do
      @org.enable_organization_projects(actor: @owner)
      project = create(:project, owner: @org)

      assert_includes Project.owner_projects_enabled, project
    end

    test "excludes project when owning org has org projects disabled" do
      # disable after creating project to ensure model validation passes
      project = create(:project, owner: @org)
      @org.disable_organization_projects(actor: @owner)

      refute_includes Project.owner_projects_enabled, project
    end

    test "excludes project when owning repo's org has repo projects disabled" do
      # disable after creating project to ensure model validation passes
      project = create(:project, owner: @repo)
      @org.disable_repository_projects(actor: @owner)

      refute_includes Project.owner_projects_enabled, project
    end

    test "ignores unrelated configuration entries with projects enabled" do
      @repo.enable_repository_projects(actor: @owner)
      @repo.set_force_push_rejection("default", @owner)
      project = create(:project, owner: @repo)

      assert_includes Project.owner_projects_enabled, project
    end

    test "ignores unrelated configuration entries with projects disabled" do
      # disable after creating project to ensure model validation passes
      project = create(:project, owner: @repo)
      @repo.disable_repository_projects(actor: @owner)
      @repo.set_force_push_rejection("default", @owner)

      refute_includes Project.owner_projects_enabled, project
    end
  end

  context ".prefer_linked_to" do
    test "puts projects linked to the specified repository first" do
      unlinked_project_1 = create(:project, owner: @org, name: "Project A")

      # Create the linked project between the two unlinked ones, so that it
      # wouldn't naturally end up as the first project no matter what
      # date-based sort was used.
      linked_project = create(:project, owner: @org, name: "Project B")
      linked_project.link_repository(@repo, @user)

      unlinked_project_2 = create(:project, owner: @org, name: "Project C")

      projects = Project.prefer_linked_to(@repo)

      # Make sure all the projects are there, regardless of order.
      assert_same_elements [linked_project, unlinked_project_1, unlinked_project_2], projects

      # Make sure the linked project comes first.
      assert_equal linked_project, projects.first
    end
  end

  context "open?" do
    test "returns true for an open project" do
      project = create(:project, closed_at: nil)
      assert_predicate project, :open?
    end

    test "returns false for a closed project" do
      project = create(:project, closed_at: Time.now)
      refute_predicate project, :open?
    end
  end

  context "closed?" do
    test "returns true for a closed project" do
      project = create(:project, closed_at: Time.now)
      assert_predicate project, :closed?
    end

    test "returns false for an open project" do
      project = create(:project, closed_at: nil)
      refute_predicate project, :closed?
    end
  end

  context "state" do
    test "returns 'open' for an open project" do
      project = create(:project, closed_at: nil)
      assert_equal "open", project.state
    end

    test "returns 'closed' for a closed project" do
      project = create(:project, closed_at: Time.now)
      assert_equal "closed", project.state
    end
  end

  context "open" do
    test "opens a closed project" do
      project = create(:project, closed_at: Time.now)

      assert project.open
      assert_predicate project.reload, :open?
    end

    test "does nothing to an open project" do
      project = create(:project, closed_at: nil)

      assert project.open
      assert_predicate project.reload, :open?
    end

    test "increments stats when reopening a migrated project" do
      project = create(:project, closed_at: Time.now, project_migration: build(:project_migration))

      assert project.open
      assert_dogstats_increment 1, "memex_project_migration.source_project_reopened"
      assert_predicate project.reload, :open?
    end

    test "block reopening of a closed, migrated project" do
      org_project = create(:org_project, owner: @owner, name: "Sample classic project board", body: "Our team board.", public: false)
      project_migration = create(:project_migration, requester: @admin, project: org_project)
      memex = assert_nothing_raised { MemexProject::Migrator.migrate!(project_migration.id) }
      project_migration.reload

      org_project.close
      org_project.open

      refute org_project.valid?
      assert_includes org_project.errors.messages[:base], "Projects (Classic) is being sunset. Closed projects that have been migrated cannot be reopened"
    end
  end

  context "close" do
    test "closes an open project" do
      project = create(:project, closed_at: nil)

      assert project.close
      assert_predicate project.reload, :closed?
    end

    test "does nothing to a closed project" do
      project = create(:project, closed_at: Time.now)

      assert project.close
      assert_predicate project.reload, :closed?
    end
  end

  test "gets a number" do
    project_1 = create(:project, owner: @repo)
    project_2 = create(:project, owner: @repo)
    assert_equal 1, project_1.number
    assert_equal 2, project_2.number

    other_repo_project = create(:project)
    assert_equal 1, other_repo_project.number
  end


  [:name, :body].each do |field|
    test "supports emoji for #{field}" do
      string_with_emoji = "[#{field}] This project is great! #{GRIN_EMOJI * 5}"
      string_with_emoji2 = "[#{field}] This project is great! " + ("\xF0\x9F\x98\x80" * 5)

      project = create(:project, field => string_with_emoji)

      assert_equal string_with_emoji, project.send(field)
      assert_multibyte_tracked_changes(project, field, string_with_emoji, string_with_emoji2)
    end
  end

  test "does not repeat numbers when last project is deleted" do
    project_1 = create(:project, owner: @repo)
    project_1.destroy
    project_2 = create(:project, owner: @repo)
    assert_equal 1, project_1.number
    assert_equal 2, project_2.number

    other_repo_project = create(:project)
    assert_equal 1, other_repo_project.number
  end

  test "does not set number before_create when project is importing?" do
    importable_project = create(:importable_project, owner: @repo, number: 1234)
    assert_equal 1234, importable_project.number
  end

  test "can destroy a project with columns and cards" do
    project = create(:project, owner: @repo)
    3.times do
      column = create(:project_column, project: project)
      5.times { create(:project_card, column: column, project: project) }
    end

    only = [AddToSearchIndexJob]
    assert perform_enqueued_jobs(only: only) { project.destroy }
    refute_predicate Project.where(id: project.id), :exists?
  end

  test "has no source_kind or source_id when created" do
    project = create(:project, owner: @repo)
    assert_nil project.source_id
    assert_nil project.source_kind
  end

  context "#enqueue_delete" do
    test "marks the project for deletion" do
      project = create(:project, owner: @repo)

      refute_predicate project, :marked_for_deletion?
      project.enqueue_delete(actor: project.creator)
      assert_predicate project, :marked_for_deletion?
    end

    test "enqueues the delete job" do
      project = create(:project, owner: @repo)
      actor = project.creator

      assert_enqueued_with(job: DeleteProjectJob, args: [project.id, actor.id]) do
        project.enqueue_delete(actor: actor)
      end
    end
  end

  context "#soft_delete!" do
    test "removes the project from the search index" do
      project = create(:project)
      assert_enqueued_with job: RemoveFromSearchIndexJob, args: ["project", project.id] do
        project.soft_delete!
      end
    end

    test "sets deleted_at" do
      project = create(:project)
      project.soft_delete!

      assert_in_delta project.deleted_at, Time.current, 1.minute
    end
  end

  test "handles projects created before we started using Sequence" do
    existing_project = create(:project, owner: @repo)
    Sequence.reset(existing_project)

    assert_equal 1, existing_project.number

    new_project = create(:project, owner: @repo)
    assert_equal 2, new_project.number
  end

  context "search_slug" do
    test "works for repository-owned projects" do
      user    = create(:user, login: "jakeboxer")
      repo    = create(:repository, name: "is-cool", owner: user)
      project = create(:project, owner: repo)

      assert_equal "jakeboxer/is-cool/#{project.number}", project.search_slug
    end

    test "works for org-owned projects" do
      org     = create(:organization, login: "blizzard")
      project = create(:project, owner: org)

      assert_equal "blizzard/#{project.number}", project.search_slug
    end

    test "works for user-owned projects" do
      user = create(:user, login: "jakeboxer")
      project = create(:project, owner: user)

      assert_equal "jakeboxer/#{project.number}", project.search_slug
    end
  end

  context "#owner_slug" do
    test "slug for repository-owned projects" do
      user    = create(:user, login: "defunkt")
      repo    = create(:repository, name: "is-cool", owner: user)
      project = create(:project, owner: repo)

      assert_equal "defunkt/is-cool", project.owner_slug
    end

    test "slug for organization-owned projects" do
      org     = create(:organization, login: "blizzard")
      project = create(:project, owner: org)

      assert_equal "blizzard", project.owner_slug
    end

    test "slug for user-owned projects" do
      user = create(:user, login: "jakeboxer")
      project = create(:project, owner: user)

      assert_equal "jakeboxer", project.owner_slug
    end
  end

  context "#writable_by?" do
    test "is false when given nil" do
      project = create(:project, owner: @repo)
      refute project.writable_by?(nil)
    end

    test "is false when user can't write to repo" do
      project = create(:project, owner: @repo)
      refute project.writable_by?(create(:user))
    end

    test "is true when user can push to repo owner" do
      project = create(:project, owner: repo = create(:repository))
      assert project.writable_by?(repo.owner)
    end
  end

  context "#repository_suggestions" do
    context "when there are linked repositories" do
      test "excludes all other org repos" do
        project = create(:org_project, owner: @org)
        column = create(:project_column, project: project)

        linked_repo = create(:repository, owner: @org)
        project.link_repository(linked_repo, @owner)

        unlinked_repo_with_card = create(:repository, owner: @org)
        issue = create(:issue, repository: unlinked_repo_with_card)
        create(:project_card, content: issue, column: column)

        # Unlinked repo without a card
        create(:repository, owner: @org)

        assert_equal [linked_repo], project.repository_suggestions(viewer: @owner)
      end
    end

    context "when there are existing issue-content cards" do
      test "includes repos associated with those cards" do
        issue   = create(:issue, repository: @repo)
        project = create(:org_project, owner: @org)
        create(:project_card, content: issue, column: create(:project_column, project: project))

        assert_includes project.repository_suggestions(viewer: @owner), @repo
      end

      test "excludes all other org repos" do
        repo2   = create(:repository, owner: @org)
        issue   = create(:issue, repository: @repo)
        project = create(:org_project, owner: @org)
        create(:project_card, content: issue, column: create(:project_column, project: project))

        assert_includes project.repository_suggestions(viewer: @owner), @repo
        refute_includes project.repository_suggestions(viewer: @owner), repo2
      end

      test "order repo suggestions by most to least amount of cards" do
        repo1 = create(:repository, owner: @org, name: "repo1")
        repo2 = create(:repository, owner: @org, name: "repo2")

        project = create(:org_project, owner: @org)
        column = create(:project_column, project: project)

        create(:project_card, content: create(:issue, repository: repo1), column: column)
        create(:project_card, content: create(:issue, repository: repo2), column: column)
        create(:project_card, content: create(:issue, repository: repo2), column: column)

        assert_equal [repo2, repo1], project.repository_suggestions(viewer: @owner)

        create(:project_card, content: create(:issue, repository: repo1), column: column)
        create(:project_card, content: create(:issue, repository: repo1), column: column)

        assert_equal [repo1, repo2], project.repository_suggestions(viewer: @owner)
      end

      test "filter when a filter is supplied" do
        repo1 = create(:repository, owner: @org, name: "YesRepo")
        repo2 = create(:repository, owner: @org, name: "NoRepo")

        project = create(:org_project, owner: @org)
        column = create(:project_column, project: project)

        create(:project_card, content: create(:issue, repository: repo1), column: column)
        create(:project_card, content: create(:issue, repository: repo2), column: column)

        assert_equal [repo1], project.repository_suggestions(viewer: @owner, filter: "yes")
      end

      test "limit returned repos" do
        project = create(:org_project, owner: @org)
        column = create(:project_column, project: project)

        (Project::MAX_SUGGESTED_REPOS - 1).times do
          create(:project_card,
            content: create(:issue,
              repository: create(:repository, owner: @org),
            ),
            column: column,
          )
        end

        assert_equal Project::MAX_SUGGESTED_REPOS - 1, project.repository_suggestions(viewer: @owner).to_a.size
        create(:project_card, content: create(:issue, repository: create(:repository, owner: @org)), column: column)
        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS, project.repository_suggestions(viewer: @owner).to_a.size
        create(:project_card, content: create(:issue, repository: create(:repository, owner: @org)), column: column)
        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS, project.repository_suggestions(viewer: @owner).to_a.size
      end

      test "limit returned repos with filtering" do
        project = create(:org_project, owner: @org)
        column = create(:project_column, project: project)

        create(:project_card,
          content: create(:issue,
            repository: create(:repository, owner: @org, name: "No1"),
          ),
          column: column,
        )
        create(:project_card,
          content: create(:issue,
            repository: create(:repository, owner: @org, name: "No2"),
          ),
          column: column,
        )
        (Project::MAX_SUGGESTED_REPOS - 1).times do |i|
          create(:project_card,
            content: create(:issue,
              repository: create(:repository, owner: @org, name: "Yes#{i}"),
            ),
            column: column,
          )
        end

        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS - 1, project.repository_suggestions(viewer: @owner, filter: "Yes").size
        create(:project_card,
          content: create(:issue,
            repository: create(:repository, owner: @org, name: "YesExtra1"),
          ),
          column: column,
        )
        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS, project.repository_suggestions(viewer: @owner, filter: "Yes").size
        create(:project_card,
          content: create(:issue,
            repository: create(:repository, owner: @org, name: "YesExtra2"),
          ),
          column: column,
        )
        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS, project.repository_suggestions(viewer: @owner, filter: "Yes").size
      end
    end

    context "when there are no issue-content cards in the project" do
      test "includes org-owned repos with issues enabled" do
        project = create(:org_project, owner: @org)

        assert_includes project.repository_suggestions(viewer: @owner), @repo
      end

      test "does not suggest repos with issues disabled" do
        @repo.update_attribute(:has_issues, false)
        project = create(:org_project, owner: @org)

        refute_includes project.repository_suggestions(viewer: @owner), @repo
      end

      test "excludes repos the viewer can access that don't belong to the org" do
        random_repo = create(:repository, owner: @owner)
        project = create(:org_project, owner: @org)

        refute_includes project.repository_suggestions(viewer: @owner), random_repo
      end

      test "filter when a filter is supplied" do
        repo1 = create(:repository, owner: @org, name: "YesRepo")
        repo2 = create(:private_repository, owner: @org, name: "YesYes")
        create(:repository, owner: @org, name: "NoRepo")

        project = create(:org_project, owner: @org)
        create(:project_column, project: project)

        assert_equal [repo1, repo2], project.repository_suggestions(viewer: @owner, filter: "yes")
      end

      test "limit returned repos" do
        project = create(:org_project, owner: @org)
        create(:project_column, project: project)

        # already got one repo in the list
        (Project::MAX_SUGGESTED_REPOS - 2).times { create(:repository, owner: @org) }
        assert_equal Project::MAX_SUGGESTED_REPOS - 1, project.repository_suggestions(viewer: @owner).size
        create(:repository, owner: @org)
        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS, project.repository_suggestions(viewer: @owner).size
        create(:repository, owner: @org)
        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS, project.repository_suggestions(viewer: @owner).size
      end

      test "limit returned repos with filtering" do
        project = create(:org_project, owner: @org)
        create(:project_column, project: project)

        create(:repository, owner: @org, name: "No1")
        create(:repository, owner: @org, name: "No2")
        (Project::MAX_SUGGESTED_REPOS - 1).times { |i| create(:repository, owner: @org, name: "Yes#{i}") }
        assert_equal Project::MAX_SUGGESTED_REPOS - 1, project.repository_suggestions(viewer: @owner, filter: "Yes").size
        create(:repository, owner: @org, name: "YesExtra1")
        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS, project.repository_suggestions(viewer: @owner, filter: "Yes").size
        create(:repository, owner: @org, name: "YesExtra2")
        @owner.reload
        assert_equal Project::MAX_SUGGESTED_REPOS, project.repository_suggestions(viewer: @owner, filter: "Yes").size
      end
    end

    test "works for user owned projects and repos" do
      project = create(:project, owner: @owner)
      column = create(:project_column, project: project)

      linked_repo = create(:repository, owner: @owner)
      project.link_repository(linked_repo, @owner)

      unlinked_repo_with_card = create(:repository, owner: @owner)
      issue = create(:issue, repository: unlinked_repo_with_card)
      create(:project_card, content: issue, column: column)

      # Unlinked repo without a card
      create(:repository, owner: @owner)

      assert_equal [linked_repo], project.repository_suggestions(viewer: @owner)
    end

    test "returns an empty array for repo projects" do
      repo = create(:repository, owner: @org)
      project = create(:org_project, owner: repo)

      assert_equal [], project.repository_suggestions(viewer: @owner)
    end
  end

  context ".valid_repo_owners_for" do
    test "includes viewer's repos belonging to orgs" do
      results = Project.valid_repo_owners_for(
        repository_ids: @owner.associated_repository_ids(min_action: :write)
      )
      assert_same_elements [@repo], results
    end

    test "includes viewer's associated repositories that they have write access to" do
      outside_user = create(:user)
      non_member_repo = create(:private_repository)
      read_member_repo = create(:private_repository, owner: @org)
      read_member_repo.add_member(outside_user, action: :read)
      write_member_repo = create(:private_repository, owner: @org)
      write_member_repo.add_member(outside_user, action: :write)

      results = Project.valid_repo_owners_for(
        repository_ids: outside_user.associated_repository_ids(min_action: :write)
      )
      assert_same_elements [write_member_repo], results
    end

    test "excludes repos where projects are disabled" do
      project = create(:project, owner: @repo)
      org_repo = create(:repository, owner: @org)
      @org.disable_repository_projects(actor: @owner)
      @repo.disable_repository_projects(actor: @owner)

      assert_empty Project.valid_repo_owners_for(
        repository_ids: @owner.associated_repository_ids(min_action: :write)
      )
    end
  end

  context ".valid_org_owners_for" do
    test "does not include orgs the viewer does not belong to" do
      non_member_org = create(:organization)
      results = Project.valid_org_owners_for(viewer: @owner)
      assert_equal [@org], results
    end

    test "excludes orgs where projects are disabled" do
      @org.disable_organization_projects(actor: @owner)

      results = Project.valid_org_owners_for(viewer: @owner)
      assert_empty results
    end

    test "returns an empty list when viewer does not belong to any orgs" do
      assert_empty Project.valid_org_owners_for(viewer: create(:user))
    end

    test "returns all the viewer's orgs when none of them have disabled org projects" do
      assert_equal [@org], Project.valid_org_owners_for(viewer: @owner)
    end
  end

  context ".query_valid_owners_for" do
    test "returns defaults if no search query is provided" do
      default = Project.valid_org_owners_for(viewer: @owner)
      default += Project.valid_repo_owners_for(
        repository_ids: @owner.associated_repository_ids(min_action: :write)
      )
      default << @owner
      results = Project.query_valid_owners_for(viewer: @owner)

      assert_same_elements default, results
      assert_same_elements [@org, @repo, @owner], default
    end

    test "includes the viewer" do
      results = Project.query_valid_owners_for(viewer: @owner)

      assert_same_elements [@org, @repo, @owner], results
    end

    test "supports filtering org by a query" do
      matching_org = create(:organization, admin: @owner, login: "match-this")
      non_matching_org = create(:organization, admin: @owner, login: "no-match")

      results = Project.query_valid_owners_for(viewer: @owner, query: "match")
      assert_includes results, matching_org
      refute_includes results, non_matching_org
    end

    test "supports filtering org by a fuzzy query" do
      matching_org = create(:organization, admin: @owner, login: "match-this")

      results = Project.query_valid_owners_for(viewer: @owner, query: "match")
      assert_includes results, matching_org
    end

    test "supports filtering for org by nwo without a repo name" do
      matching_org = create(:organization, admin: @owner, login: "match-this")

      results = Project.query_valid_owners_for(viewer: @owner, query: "ma/")
      assert_includes results, matching_org
    end

    test "excludes partial org match results when there is an exact match" do
      matching_org = create(:organization, admin: @owner, login: "slothlandia")
      non_matching_org = create(:organization, admin: @owner, login: "sloth")

      results = Project.query_valid_owners_for(viewer: @owner, query: "slothlandia")
      assert_includes results, matching_org
      refute_includes results, non_matching_org
    end

    test "excludes partial org substring matches" do
      matching_org = create(:organization, admin: @owner, login: "sloth-party")
      non_matching_org = create(:organization, admin: @owner, login: "party-sloth")

      results = Project.query_valid_owners_for(viewer: @owner, query: "sloth")
      assert_includes results, matching_org
      refute_includes results, non_matching_org
    end

    test "supports repo filtering by a query matching a repository name" do
      matching_repo = create(:repository, owner: @org, name: "match-this")
      non_matching_repo = create(:repository, owner: @org, name: "no-match")

      results = Project.query_valid_owners_for(viewer: @owner, query: "match")
      assert_includes results, matching_repo
      refute_includes results, non_matching_repo
    end

    test "nwo queries scope repo results to org when there is an exact match" do
      matching_org = create(:organization, admin: @owner, login: "slothlandia")
      exact_match_repo = create(:repository, owner: matching_org, name: "taco")
      matching_repo = create(:repository, owner: matching_org, name: "taco-time")
      non_matching_fork = create(:repository, owner: @owner, name: "taco")

      results = Project.query_valid_owners_for(viewer: @owner, query: "slothlandia/taco")
      assert_includes results, matching_repo
      assert_includes results, exact_match_repo
      refute_includes results, non_matching_fork
    end

    test "nwo queries scope repos to user when there is an exact match" do
      exact_match_repo = create(:repository, owner: @owner, name: "taco")
      matching_repo = create(:repository, owner: @owner, name: "taco-time")
      non_matching_fork = create(:repository, owner: @org, name: "taco")

      results = Project.query_valid_owners_for(viewer: @owner, query: "#{@owner.name}/taco")
      assert_includes results, matching_repo
      assert_includes results, exact_match_repo
      refute_includes results, non_matching_fork
    end

    test "nwo queries repos scoped to another user include repos the viewer is a collaborator on" do
      other_user = create(:user, login: "slothette")
      excluded_repo = create(:repository, owner: other_user, name: "taco")
      collaborator_repo = create(:repository, owner: other_user, name: "taco-time")
      collaborator_repo.add_member(@owner)

      results = Project.query_valid_owners_for(viewer: @owner, query: "slothette/taco")
      refute_includes results, excluded_repo
      assert_includes results, collaborator_repo
    end

    test "supports filtering repos by nwo without an owner" do
      matching_repo = create(:repository, owner: @org, name: "match-this")

      results = Project.query_valid_owners_for(viewer: @owner, query: "/match")
      assert_includes results, matching_repo
    end

    test "does not filter repo name when there is only an owner name match" do
      matching_org = create(:organization, admin: @owner, login: "slothlandia")
      matching_repo = create(:repository, owner: matching_org, name: "yay")
      non_matching_repo = create(:repository, owner: matching_org, name: "sloth")

      results = Project.query_valid_owners_for(viewer: @owner, query: "slothlandia")
      assert_includes results, matching_repo
      assert_includes results, non_matching_repo
    end

    test "excludes partial repo substring matches" do
      matching_repo = create(:repository, owner: @org, name: "match-this")
      non_matching_repo = create(:repository, owner: @org, name: "no-match")

      results = Project.query_valid_owners_for(viewer: @owner, query: "match")
      assert_includes results, matching_repo
      refute_includes results, non_matching_repo
    end

    test "excludes exact match users the viewer does have collab access to" do
      exact_user = create(:user, login: "sloth")
      matching_repo = create(:repository, owner: @owner, name: "sloth")
      another_matching_repo = create(:repository, owner: @owner, name: "slothlandia")

      results = Project.query_valid_owners_for(viewer: @owner, query: "sloth")
      assert_same_elements [matching_repo, another_matching_repo, @owner], results
      refute_includes results, exact_user
    end

    test "excludes exact match orgs the viewer does not have access to" do
      exact_org = create(:organization, login: "sloth", admin: create(:user))
      matching_repo = create(:repository, owner: @owner, name: "sloth")
      another_matching_repo = create(:repository, owner: @owner, name: "slothlandia")

      results = Project.query_valid_owners_for(viewer: @owner, query: "sloth")
      assert_same_elements [matching_repo, another_matching_repo, @owner], results
      refute_includes results, exact_org
    end

    test "supports filtering user by a query" do
      matching_user = create(:user, login: "match-this")
      results = Project.query_valid_owners_for(viewer: matching_user, query: "match")

      assert_includes results, matching_user
    end
  end

  context "applying a template" do
    test "works on an empty Project" do
      project = create(:project)
      assert_empty project.columns

      template = ProjectTemplate.load("basic_kanban")
      project.apply_template(template)
      assert_equal template.columns.length, project.columns.length
      assert_equal 3, project.cards.length
      assert_equal Project::SOURCE_KIND_GITHUB_TEMPLATE, project.source_kind
      assert_equal ProjectTemplate::SOURCE_MAPPINGS[template.class.to_s], project.source_id
    end

    test "creates and saves the columns from template data" do
      project = create(:project)
      template = ProjectTemplate.load("basic_kanban")
      project.apply_template(template)

      assert_equal template.columns.length, project.columns.length
      assert_same_elements project.columns.map(&:name), template.columns.map(&:name)
    end

    test "creates and saves the cards in the correct columns" do
      project = create(:project)
      template = ProjectTemplate.load("basic_kanban")
      project.apply_template(template)

      assert_equal 3, project.cards.length
      assert_empty project.columns[1].cards
      assert_empty project.columns[2].cards
    end

    test "creates and saves cards and workflows for automated kanban" do
      project = create(:project)
      template = ProjectTemplate.load("automated_kanban_v2")
      project.apply_template(template)

      assert_equal 3, project.cards.length
      assert_equal 7, project.project_workflows.length
    end

    test "prioritizes cards" do
      project = create(:project)
      template = ProjectTemplate.load("basic_kanban")
      project.apply_template(template)

      refute_empty project.cards
      project.cards.each { |card| assert_predicate card, :prioritized? }
    end

    test "does not apply the template if the project has columns" do
      project = create(:project)
      column = create(:project_column, project: project)
      template = ProjectTemplate.load("basic_kanban")

      refute project.apply_template(template)
      assert project.errors[:base].any?
    end

    test "does not apply the template if the template is invalid" do
      project = create(:project)
      refute project.apply_template("sloth")
      assert project.errors[:base].any?
    end
  end

  context "repo name filtering" do
    test "case insensitive filter" do
      project = create(:org_project, owner: @org)
      repos = %w[hello HelloWorld goodbye].map do |n|
        create(:repository, owner: @org, name: n)
      end
      assert_equal %w[hello HelloWorld], project.apply_repo_name_filter(repos, "Hello").map(&:name)
      assert_equal %w[hello HelloWorld], project.apply_repo_name_filter(repos, "hello").map(&:name)
    end

    test "repos match on partial string" do
      project = create(:org_project, owner: @org)
      repos = %w(hello worldHello CamelCase snake_case kebab-case 123mixED_case BuMPY_CAse123).map do |n|
        create(:repository, owner: @org, name: n)
      end
      assert_equal %w(hello worldHello), project.apply_repo_name_filter(repos, "hello").map(&:name)
      assert_equal %w(CamelCase), project.apply_repo_name_filter(repos, "melca").map(&:name)
      assert_equal %w(snake_case), project.apply_repo_name_filter(repos, "ke_ca").map(&:name)
      assert_equal %w(kebab-case), project.apply_repo_name_filter(repos, "ab-ca").map(&:name)
      assert_equal %w(123mixED_case BuMPY_CAse123), project.apply_repo_name_filter(repos, "123").map(&:name)
    end

    test "repos come back in order and limited" do
      project = create(:org_project, owner: @org)
      names = (1..19).map { |i| "hello#{i}" }
      repos = names.map { |n| create(:repository, owner: @org, name: n) }
      repos << create(:repository, owner: @org, name: "goodbye1")
      repos << create(:repository, owner: @org, name: "goodbye2")
      repos << create(:repository, owner: @org, name: "helloExtra1")
      repos << create(:repository, owner: @org, name: "helloExtra2")
      names << "helloExtra1"
      assert_equal names, project.apply_repo_name_filter(repos, "hello").map(&:name)
    end
  end

  context "#can_change_owner_to?" do
    test "returns false if new owner is the same as old owner" do
      project = build(:project, owner: @owner)

      refute project.can_change_owner_to?(@owner)
    end

    test "returns false if new owner is a repository and project contains cards linking to other repos" do
      project = create(:project, owner: @owner)
      repo = create(:repository, owner: @owner)
      another_repo = create(:repository, owner: @owner)
      create(:project_card, content: create(:issue, repository: another_repo), column: create(:project_column, project: project))

      refute project.can_change_owner_to?(repo)
    end

    test "returns true if new owner is a repository and project does not contain cards linking to other repos" do
      project = create(:project, owner: @owner)
      repo = create(:repository, owner: @owner)
      create(:project_card, content: create(:issue, repository: repo), column: create(:project_column, project: project))

      assert project.can_change_owner_to?(repo)
    end

    test "returns false if new owner is a user and project contains cards linking to repos user does not have access" do
      project = create(:project, owner: @owner)
      target_owner = create(:user)
      repo = create(:repository, owner: @owner)
      create(:project_card, content: create(:issue, repository: repo), column: create(:project_column, project: project))

      refute project.can_change_owner_to?(target_owner)
    end

    test "returns true if new owner is a user and project contains cards linking to repos user has access" do
      project = create(:project, owner: @owner)
      target_owner = create(:user)
      repo = create(:repository, owner: target_owner)
      create(:project_card, content: create(:issue, repository: repo), column: create(:project_column, project: project))

      assert project.can_change_owner_to?(target_owner)
    end

    test "returns true if new owner is a user and project contains cards linking to repos user does not have access but there is a move work in progress for it" do
      project = create(:project, owner: @owner)
      target_owner = create(:organization, admin: @owner)
      repo = create(:repository, owner: @owner)
      create(:project_card, content: create(:issue, repository: repo), column: create(:project_column, project: project))
      move_work = create(:move_work, :started, user: @owner, origin: @owner, target: target_owner)
      create(:move_work_item, resource: project, move_work: move_work)

      assert project.can_change_owner_to?(target_owner)
    end
  end

  context "tracking" do
    test "increments a counter in Datadog for org-owned projects" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      create(:org_project)
      assert_equal 1,
        GitHub.dogstats.increments("project.with_organization_owner.created").length
    end

    test "increments a counter in Datadog for repo-owned projects" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      create(:project)
      assert_equal 1,
        GitHub.dogstats.increments("project.with_repository_owner.created").length
    end

    test "increments a counter in Datadog for user-owned projects" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      create(:user_project)

      assert_equal 1, GitHub.dogstats.increments("project.with_user_owner.created").length
    end
  end

  context "#change_owner!" do
    test "can move empty project" do
      repo = create(:org_owned_repository)
      org = repo.owner
      project = create(:project, owner: repo)

      assert_equal repo, project.owner
      assert project.change_owner!(new_owner: org)
      assert_equal org, project.owner
    end

    test "can move a project with only notes to a different top-level owner" do
      repo = create(:org_owned_repository)
      project = create(:project, owner: repo)
      column = create(:project_column, project: project)
      user = create(:user)
      create(:note_project_card, column: column)

      assert project.change_owner!(new_owner: user)
      assert_equal user, project.owner
    end

    test "clears permissions from org projects when transferring to a user" do
      org = create(:organization)
      project = create(:project, owner: org)
      read_user = create(:user)

      project.update_user_permission(read_user, :read)
      assert project.readable_by?(read_user)

      new_owner = create(:user)
      perform_enqueued_jobs(only: [ClearAbilitiesJob]) { project.change_owner!(new_owner: new_owner) }

      project.reload
      refute project.readable_by?(read_user)
    end

    test "assigns the next number in the sequence from the new owner" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      5.times { create(:project, owner: org) }
      project = create(:project, owner: repo)

      assert_same_elements 1..5, org.projects.pluck(:number)

      project.change_owner!(new_owner: org)
      assert_equal 6, project.reload.number

      assert_equal 7, create(:project, owner: org).number
    end

    test "can't move project to its existing owner" do
      project = create(:project)
      refute project.change_owner!(new_owner: project.owner)
    end

    test "links the repo when moved to a repo's owner" do
      repo = create(:org_owned_repository)
      org  = repo.owner
      project = create(:project, owner: repo)
      column = create(:project_column, project: project)
      create(:project_card, content: create(:issue, repository: repo), column: column)
      create(:note_project_card, column: column)

      project.change_owner!(new_owner: org)

      assert_equal org, project.owner
      assert_equal 1, project.linked_repositories.count
    end

    test "removes project links when transferring from a top-level owner to a repo" do
      project = create(:project, owner: @org)
      project.link_repository(@repo, @owner)

      assert_equal 1, project.linked_repositories.count

      perform_enqueued_jobs(only: [UnlinkAllProjectRepositoryLinksJob]) do
        project.change_owner!(new_owner: @repo)
      end
      project.reload

      assert_equal 0, project.linked_repositories.count
    end

    test "does not link the repo when moved to a different top-level owner" do
      repo = create(:org_owned_repository)
      org  = repo.owner
      project = create(:project, owner: repo)
      column = create(:project_column, project: project)
      create(:note_project_card, column: column)

      user = create(:user)
      project.change_owner!(new_owner: user)

      assert_equal user, project.owner
      assert_equal 0, project.linked_repositories.count
    end

    test "moves an org-owned project to a repo if all issue cards belong to that repo" do
      repo = create(:org_owned_repository)
      org  = repo.owner
      project = create(:project, owner: org)
      column = create(:project_column, project: project)
      create(:project_card, content: create(:issue, repository: repo), column: column)
      create(:note_project_card, column: column)

      assert_equal org, project.owner

      project.change_owner!(new_owner: repo)

      assert_equal repo, project.owner
      assert_equal "Repository", project.owner_type
      assert_includes repo.projects, project
      refute_includes org.projects, project
    end

    test "moves a user-owned project to a repo if all issue cards belong to that repo" do
      repo = create(:repository, owner: @owner)
      project = create(:project, owner: @owner)
      column = create(:project_column, project: project)
      create(:project_card, content: create(:issue, repository: repo), column: column)
      create(:note_project_card, column: column)

      assert_equal @owner, project.owner

      project.change_owner!(new_owner: repo)

      assert_equal repo, project.owner
      assert_equal "Repository", project.owner_type
      assert_includes repo.projects, project
      refute_includes @owner.projects, project
    end

    test "fails to move an org-owned project to a repo if any issue cards belong to a different repo" do
      org  = create(:organization)
      repo = create(:org_owned_repository, owner: org)
      other_repo = create(:org_owned_repository, owner: org)
      project = create(:project, owner: org)
      column = create(:project_column, project: project)
      create(:project_card, content: create(:issue, repository: repo), column: column)
      create(:project_card, content: create(:issue, repository: other_repo), column: column)

      assert_equal org, project.owner

      refute project.change_owner!(new_owner: repo)

      assert_equal org, project.owner
    end

    test "fails to move a user-owned project to a repo if any issue cards belong to a different repo" do
      repo = create(:repository, owner: @owner)
      other_repo = create(:repository, owner: @owner)
      project = create(:project, owner: @owner)
      column = create(:project_column, project: project)
      create(:project_card, content: create(:issue, repository: repo), column: column)
      create(:project_card, content: create(:issue, repository: other_repo), column: column)

      assert_equal @owner, project.owner

      refute project.change_owner!(new_owner: repo)

      assert_equal @owner, project.owner
    end

    test "moves a repository-owned project to an org" do
      repo = create(:org_owned_repository)
      org  = repo.owner
      project = create(:project, owner: repo)

      assert_equal repo, project.owner

      project.change_owner!(new_owner: org)

      assert_equal org, project.owner
      assert_equal "Organization", project.owner_type
      assert_includes org.projects, project
      refute_includes repo.projects, project
    end

    test "moves a repository-owned project to a user" do
      repo = create(:repository, owner: @owner)
      project = create(:project, owner: repo)

      assert_equal repo, project.owner

      project.change_owner!(new_owner: @owner)

      assert_equal @owner, project.owner
      assert_equal "User", project.owner_type
      assert_includes @owner.projects, project
      refute_includes repo.projects, project
    end
  end

  context "#transform_owner_type!" do
    test "sets the correct owner type" do
      project = create(:project, owner: @owner)
      new_creator = create(:user)

      assert_equal @owner, project.owner
      assert_equal "User", project.owner_type

      project.transform_owner_type!(owner: @org, new_creator: new_creator)
      project.reload

      assert_equal @org, project.owner
      assert_equal "Organization", project.owner_type
    end

    test "individual collaborators do not lose access" do
      project = create(:project, owner: @owner)
      new_creator = create(:user)
      collab = create(:user)
      project.update_user_permission(collab, :write)

      assert project.writable_by?(collab)

      project.transform_owner_type!(owner: @org, new_creator: new_creator)
      project.reload

      assert project.writable_by?(collab)
    end

    test "changes the creator and adds them as admin" do
      project = create(:project, owner: @owner)
      new_creator = create(:user)

      assert_equal @owner, project.creator

      project.transform_owner_type!(owner: @org, new_creator: new_creator)
      project.reload

      assert_equal new_creator, project.creator
      assert project.adminable_by?(@owner)
    end

    test "raises an error with a new owner that's a repo" do
      project = create(:project, owner: @org)

      assert_raises "Cannot transform Organization project to Repository project" do
        project.transform_owner_type!(owner: @repo, new_creator: @owner)
      end
    end

    test "raises an error with a new owner that's a user" do
      project = create(:project, owner: @org)

      assert_raises "Cannot transform Organization project to User project" do
        project.transform_owner_type!(owner: @owner, new_creator: @owner)
      end
    end
  end

  context "link_repository" do
    test "creates a new ProjectRepositoryLink" do
      project = create(:project, owner: @org)
      repo = create(:repository, owner: @org)

      project.link_repository(repo, @owner)
      link = project.project_repository_links.first

      assert_equal 1, project.project_repository_links.count
      assert_equal repo.id, link.repository_id
    end

    test "errors if the maximum link count is exceeded" do
      project = create(:project, owner: @org)
      excess_repo = create(:repository, owner: @org)
      Project.stub_const(:MAX_REPOSITORY_LINKS, 3) do
        repos = create_list(:repository, Project::MAX_REPOSITORY_LINKS, owner: @org)
        repos.each { |repo| create(:project_repository_link, project: project, repository: repo, creator: @owner) }

        assert_raises ActiveRecord::RecordInvalid do
          project.link_repository(excess_repo, @creator)
        end
      end
    end

    test "raises an error if the link is invalid" do
      project = create(:project, owner: @org)
      invalid_repo = create(:repository, owner: @owner)

      assert_raises ActiveRecord::RecordInvalid do
        project.link_repository(invalid_repo, @owner)
      end
    end
  end

  context "unlink_repository" do
    test "deletes an existing ProjectRepositoryLink" do
      project = create(:project, owner: @org)
      repo = create(:repository, owner: @org)
      project.link_repository(repo, @owner)

      project.unlink_repository(repo)
      refute_predicate ProjectRepositoryLink.where(repository_id: repo.id, project_id: project.id), :exists?
    end

    test "raises an error if the link is not found" do
      project = create(:project, owner: @org)
      another_repo = create(:repository, owner: @org)

      assert_raises ActiveRecord::RecordNotFound do
        project.unlink_repository(another_repo)
      end
    end
  end

  context "unlink_repositories" do
    test "enqueues a job" do
      project = create(:project, owner: @org)
      project.link_repository(@repo, @owner)

      assert_enqueued_with(
        job: UnlinkAllProjectRepositoryLinksJob,
        args: [project.id, @owner.id],
      ) do
        project.unlink_repositories
      end
    end

    test "deletes all existing ProjectRepositoryLinks" do
      project = create(:project, owner: @org)
      project.link_repository(@repo, @owner)

      perform_enqueued_jobs(only: [UnlinkAllProjectRepositoryLinksJob]) do
        project.unlink_repositories
      end

      refute_predicate ProjectRepositoryLink.where(repository_id: @repo.id, project_id: project.id), :exists?
    end
  end

  context "suggested_repositories_to_link" do
    test "suggests repositories with more cards in the project first" do
      project = create(:project, owner: @org)

      repo_with_fewer_cards = create(:repository, owner: @org)
      create(:project_card,
        project: project,
        content: create(:issue, repository: repo_with_fewer_cards),
      )

      repo_with_more_cards = create(:repository, owner: @org)
      2.times do
        create(:project_card,
          project: project,
          content: create(:issue, repository: repo_with_more_cards),
        )
      end

      assert_equal [repo_with_more_cards, repo_with_fewer_cards], project.suggested_repositories_to_link(actor: @owner)
    end

    test "excludes repositories with no cards in the project" do
      project = create(:project, owner: @org)

      repo_with_cards = create(:repository, owner: @org)
      create(:project_card,
        project: project,
        content: create(:issue, repository: repo_with_cards),
      )

      repo_without_cards = create(:repository, owner: @org)
      create(:issue, repository: repo_without_cards)

      assert_equal [repo_with_cards], project.suggested_repositories_to_link(actor: @owner)
    end

    test "excludes already-linked repositories" do
      project = create(:project, owner: @org)

      linked_repo = create(:repository, owner: @org)
      create(:project_card,
        project: project,
        content: create(:issue, repository: linked_repo),
      )
      project.link_repository(linked_repo, @owner)

      unlinked_repo = create(:repository, owner: @org)
      create(:project_card,
        project: project,
        content: create(:issue, repository: unlinked_repo),
      )

      assert_equal [unlinked_repo], project.suggested_repositories_to_link(actor: @owner)
    end

    test "excludes repositories that the actor cannot see" do
      project = create(:project, owner: @org)

      visible_repo = create(:private_repository, owner: @org)
      create(:project_card,
        project: project,
        content: create(:issue, repository: visible_repo),
      )

      hidden_repo = create(:private_repository, owner: @org)
      create(:project_card,
        project: project,
        content: create(:issue, repository: hidden_repo),
      )

      actor = create(:user)
      project.update_user_permission(actor, :write)
      visible_repo.add_member(actor, action: :read)

      assert_equal [visible_repo], project.suggested_repositories_to_link(actor: actor)
    end
  end

  context "instrumentation" do
    test "instruments project creation" do
      events = subscribe "project.create"
      project = create(:project, owner: @org, creator: @owner)

      expected_payload = {
        project: project.name,
        project_id: project.id,
        spammy: false,
        org: @org.name,
        org_id: @org.id,
        actor: @owner.login,
        actor_id: @owner.id,
        rank: 1,
      }
      assert event = events.pop, "an event was expected"
      assert_equal "project.create", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments project rename" do
      events = subscribe "project.rename"
      project = create(:project, owner: @org, creator: @owner, name: "hello")
      project.update_attribute(:name, "hi there")

      assert event = events.pop, "an event was expected"
      assert_equal "project.rename", event.name
      assert_equal "hello", event.payload[:old_name]
    end

    test "instruments project access change" do
      events = subscribe "project.access"
      project = create(:project, owner: @org, creator: @owner, name: "hello", public: true)
      project.update_attribute(:public, false)

      assert event = events.pop, "an event was expected"
      assert_equal "project.access", event.name
      assert_equal "private", event.payload[:access]
    end

    test "instruments project org permission change" do
      events = subscribe "project.update_org_permission"
      project = create(:project, owner: @org, creator: @owner, name: "hello", public: true)
      project.update_org_permission(:write)

      assert event = events.pop, "an event was expected"
      assert_equal "project.update_org_permission", event.name
      assert_equal @org.id, event.payload[:org_id]
      assert_equal :write, event.payload[:changes][:permission]
    end

    test "instruments project team permission change" do
      events = subscribe "project.update_team_permission"
      project = create(:project, owner: @org, creator: @owner, name: "hello", public: true)
      team = create(:team, organization: @org)
      team.add_project(project, :write)

      assert event = events.pop, "an event was expected"
      assert_equal "project.update_team_permission", event.name
      assert_equal team.id, event.payload[:team_id]
      assert_equal :write, event.payload[:changes][:permission]
    end

    test "instruments project user permission change" do
      events = subscribe "project.update_user_permission"
      project = create(:project, owner: @org, creator: @owner, name: "hello", public: true)
      collab = create(:user, login: "collab")
      project.update_user_permission(collab, :write)

      assert event = events.pop, "an event was expected"
      assert_equal "project.update_user_permission", event.name
      assert_equal collab.id, event.payload[:user_id]
      assert_equal :write, event.payload[:changes][:permission]
    end

    test "instruments project update" do
      events = subscribe "project.update"
      project = create(:project, owner: @org, creator: @owner, track_progress: false)
      project.update(body: "this is the end", track_progress: true)

      assert event = events.pop, "an event was expected"
      assert_equal "project.update", event.name
      refute_nil event.payload[:changes]
      assert_nil event.payload[:changes][:old_body]
      assert_equal "this is the end", event.payload[:changes][:body]
      assert_equal false, event.payload[:changes][:old_track_progress]
      assert_equal true, event.payload[:changes][:track_progress]
    end

    test "instruments project close" do
      events = subscribe "project.close"
      project = create(:project, owner: @org, creator: @owner)
      project.close

      assert event = events.pop, "an event was expected"
      assert_equal "project.close", event.name
      assert_nil event.payload[:changes]
    end

    test "instruments project open" do
      events = subscribe "project.open"
      project = create(:project, owner: @org, creator: @owner)
      project.close
      project.open

      assert event = events.pop, "an event was expected"
      assert_equal "project.open", event.name
      assert_nil event.payload[:changes]
    end

    test "instruments project destroy" do
      events = subscribe "project.delete"
      project = create(:project, owner: @org, creator: @owner)

      expected_payload = {
        project: project.name,
        project_id: project.id,
        org: @org.name,
        org_id: @org.id,
        rank: 1,
      }
      project.destroy

      assert event = events.pop, "an event was expected"
      assert_equal "project.delete", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments linking a repository" do
      events = subscribe "project.link"
      project = create(:project, owner: @org, creator: @owner)
      project.link_repository(@repo, @owner)

      expected_payload = {
        project: project.name,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        actor: @owner.login,
        actor_id: @owner.id,
        rank: 1,
        project_id: project.id,
        org: @org.login,
        org_id: @org.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "project.link", event.name

      assert_equal expected_payload, event.payload
    end

    test "instruments unlinking a repository" do
      events = subscribe "project.unlink"
      project = create(:project, owner: @org, creator: @owner)
      project.link_repository(@repo, @owner)
      project.unlink_repository(@repo)

      expected_payload = {
        project: project.name,
        repo: @repo.nwo,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        actor: @owner.login,
        actor_id: @owner.id,
        rank: 1,
        project_id: project.id,
        org: @org.login,
        org_id: @org.id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal "project.unlink", event.name

      assert_equal expected_payload, event.payload
    end
  end

  context "Workflow actions" do
    test "current_workflow_action_id returns based on context" do
      project = create(:project, owner: @org, creator: @owner)
      assert_nil project.current_workflow_action_id
      GitHub.context.push(project_workflow_action_id: 1234) do
        assert_equal 1234, project.current_workflow_action_id
      end
    end
  end

  context "#set_search_query_for" do
    {
      "Russian characters": "главного экрана",
      "4 byte emoji": "🍷omg",
      "another emoji": "🎭 more emoji",
      "example from an exception": 'is:open type:issue -label:\"type: enhancement 💡\"',
    }.each do |description, query|
      test "does not raise when there are #{description} in the query" do
        assert_no_query_warnings do
          project = create(:project, owner: @org, creator: @owner)
          assert_nothing_raised do
            project.set_search_query_for(@owner, query: query.dup)
          end
          assert_equal query, project.search_query_for(@owner)
        end
      end
    end
  end

  context "path" do
    test "returns path for org" do
      project = create(:project, owner: @org, creator: @org)
      assert_includes project.path, "orgs"
    end

    test "returns path for user" do
      project = create(:project, owner: @owner, creator: @owner)
      assert_includes project.path, "user"
    end

    test "returns path for repository" do
      project = create(:project, owner: @repo)
      assert_includes project.path, "repo"
    end
  end

  context "empty?" do
    test "returns truthy if the project is empty" do
      project = create(:project, owner: @repo)
      assert project.empty?
    end

    test "returns falsy if the project is not empty" do
      project = create(:project, owner: @repo)

      3.times do
        column = create(:project_column, project: project)
        5.times { create(:project_card, column: column, project: project) }
      end

      refute project.empty?
    end
  end


  test "is deleted with repository" do
    project = create(:project, owner: @repo)
    other_project = create(:project)
    other_other_project = create(:project, owner: @owner)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [project]
      config.expect_not_destroyed = [other_project, other_other_project]
    end
  end
end
