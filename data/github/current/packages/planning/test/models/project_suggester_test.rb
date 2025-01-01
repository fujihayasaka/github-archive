# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectSuggesterTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :verified)
    @issue = create(:issue)

    MemexHelpers.setup_organization_wide_access_for_projects("project_writer")
  end

  setup do
    GitHub.context.push(actor_id: @user.id)
  end

  context "#repository_projects" do
    test "includes projects owned by repositories the viewer owns" do
      repo = create(:repository, owner: @user)
      project = create(:project, owner: repo)
      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [project], suggester.repository_projects
    end

    test "includes projects owned by repositories the viewer has write access to" do
      repo = create(:repository)
      repo.add_member(@user)

      project = create(:project, owner: repo)
      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [project], suggester.repository_projects
    end

    test "does not include by default projects owned by repositories the viewer can't write to" do
      repo = create(:repository)
      project = create(:project, owner: repo)
      refute project.writable_by?(@user), "setup is wrong"

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_empty suggester.repository_projects
    end

    test "does include projects owned by repositories the viewer can read, if querying readable" do
      repo = create(:repository)
      repo.add_member(@user, action: :read)
      project = create(:project, owner: repo)

      assert project.readable_by?(@user), "setup is wrong"
      refute project.writable_by?(@user), "setup is wrong"

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [project], suggester.repository_projects(min_permission_level: "read")
    end

    test "does not include projects owned by repositories the viewer can't see" do
      repo = create(:private_repository)
      project = create(:project, owner: repo)
      refute project.writable_by?(@user), "setup is wrong"

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_empty suggester.repository_projects
    end

    test "does not include any projects if the viewer is logged out" do
      repo = create(:repository)
      create(:project, owner: repo)

      suggester = ProjectSuggester.new(viewer: nil, context: repo)

      assert_empty suggester.repository_projects
    end

    test "does not include closed projects owned by repositories" do
      repo = create(:repository, owner: @user)
      project = create(:project, owner: repo, closed_at: Time.now)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_predicate project, :closed?
      assert_empty suggester.repository_projects
    end

    test "prefills the project owner" do
      repo = create(:repository, owner: @user)
      create(:project, owner: repo)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_predicate suggester.repository_projects.first.association(:owner), :loaded?
    end

    test "includes projects classic and memex projects" do
      repo = create(:repository, owner: @user)
      project = create(:project, owner: repo)

      memex_project = create(:memex_project, owner: @user)
      MemexProjectLink.new(source: repo, memex_project: memex_project).save

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [project, memex_project], suggester.repository_projects
    end

    test "includes memex projects that the viewer has (write or read) access to" do
      org = create(:organization)
      repo = create(:repository, owner: org)

      memex_project_read = create(:memex_project, owner: org)
      MemexProjectLink.new(source: repo, memex_project: memex_project_read).save
      Permissions::Granters::RoleGranter.new(
        actor: @user, target: memex_project_read, role: Role.project_reader_role
      ).grant_unless_exists!

      memex_project_write = create(:memex_project, owner: org)
      MemexProjectLink.new(source: repo, memex_project: memex_project_write).save
      Permissions::Granters::RoleGranter.new(
        actor: @user, target: memex_project_write, role: Role.project_writer_role
      ).grant_unless_exists!

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [memex_project_write], suggester.repository_projects

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)
      assert_same_elements [memex_project_read, memex_project_write], suggester.repository_projects(min_permission_level: "read")
    end

    test "returns memex projects that are templates when only_memex_templates is true" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      MemexProjectLink.new(source: repo, memex_project: memex_project).save
      public_memex_project = create(:memex_project, public: true, owner: org)
      MemexProjectLink.new(source: repo, memex_project: public_memex_project).save
      memex_project_with_template = create(:memex_project, owner: org)
      memex_project_template = create(:memex_template, memex_project: memex_project_with_template)
      MemexProjectLink.new(source: repo, memex_project: memex_project_with_template).save

      suggester = ProjectSuggester.new(viewer: @user, context: repo, only_memex_templates: true, load_memex_projects: true)

      assert_same_elements [memex_project_with_template], suggester.repository_projects
    end

    test "returns memex projects and templates when only_memex_templates is false" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      MemexProjectLink.new(source: repo, memex_project: memex_project).save
      public_memex_project = create(:memex_project, public: true, owner: org)
      MemexProjectLink.new(source: repo, memex_project: public_memex_project).save
      memex_project_with_template = create(:memex_project, owner: org)
      memex_project_template = create(:memex_template, memex_project: memex_project_with_template)
      MemexProjectLink.new(source: repo, memex_project: memex_project_with_template).save

      suggester = ProjectSuggester.new(viewer: @user, context: repo, only_memex_templates: false, load_memex_projects: true)

      assert_same_elements [memex_project, memex_project_with_template, public_memex_project], suggester.repository_projects
    end

    test "includes public memex projects" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      MemexProjectLink.new(source: repo, memex_project: memex_project).save
      public_memex_project = create(:memex_project, public: true, owner: org)
      MemexProjectLink.new(source: repo, memex_project: public_memex_project).save

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [memex_project, public_memex_project], suggester.repository_projects
    end

    test "does not include deleted memex projects" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      MemexProjectLink.new(source: repo, memex_project: memex_project).save
      deleted_memex_project = create(:memex_project, owner: org, deleted_at: Time.now)
      MemexProjectLink.new(source: repo, memex_project: deleted_memex_project).save

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [memex_project], suggester.repository_projects
    end

    test "prefills the project owner for memex projects" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      MemexProjectLink.new(source: repo, memex_project: memex_project).save

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_predicate suggester.repository_projects.first.association(:owner), :loaded?
    end
  end

  context "#organization_projects" do
    test "includes projects owned by the repo's org that the viewer has write access to" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      repo.add_member(@user, action: :write)
      project = create(:project, owner: org)
      project.update_user_permission(@user, :write)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [project], suggester.organization_projects
    end

    test "prioritizes linked repositories" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      repo.add_member(@user, action: :write)

      unlinked_project_1 = create(:project, owner: org, name: "Project A")
      unlinked_project_1.update_user_permission(@user, :write)

      # Create the linked project between the two unlinked ones, so that it
      # wouldn't naturally end up as the first project no matter what
      # date-based sort was used.
      linked_project = create(:project, owner: org, name: "Project B")
      linked_project.update_user_permission(@user, :write)
      linked_project.link_repository(repo, @user)

      unlinked_project_2 = create(:project, owner: org, name: "Project C")
      unlinked_project_2.update_user_permission(@user, :write)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)
      projects = suggester.organization_projects

      # Make sure all the projects are there, regardless of order.
      assert_same_elements [linked_project, unlinked_project_1, unlinked_project_2], projects

      # Make sure the linked project comes first.
      assert_equal linked_project, projects.first
    end

    test "does not include projects owned by the repo's org that the viewer doesn't have write access to" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      repo.add_member(@user, action: :write)
      project = create(:project, owner: org)
      project.update_user_permission(@user, :read)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_empty suggester.organization_projects
    end

    test "does include projects owned by the repo's org that the viewer does have read access to, if querying readable" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      repo.add_member(@user, action: :write)
      project = create(:project, owner: org)
      project.update_user_permission(@user, :read)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [project], suggester.organization_projects(min_permission_level: "read")
    end

    test "does not include any projects if the viewer is logged out" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      create(:project, owner: org)

      suggester = ProjectSuggester.new(viewer: nil, context: repo)

      assert_empty suggester.organization_projects
    end

    test "does not include closed projects" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      repo.add_member(@user, action: :write)
      project = create(:project, owner: org, closed_at: Time.now)
      project.update_user_permission(@user, :write)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_predicate project, :closed?
      assert_empty suggester.organization_projects
    end

    test "prefills the project owner" do
      org = create(:organization)
      repo = create(:repository, owner: org)
      repo.add_member(@user, action: :write)
      project = create(:project, owner: org)
      project.update_user_permission(@user, :write)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_predicate suggester.organization_projects.first.association(:owner), :loaded?
    end

    test "includes memex projects that the viewer has write access to" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [memex_project], suggester.organization_projects
    end

    test "includes public memex projects" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      public_memex_project = create(:memex_project, public: true, owner: org)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [memex_project, public_memex_project], suggester.organization_projects
    end

    test "does not include public projects if user is not a member" do
      org = create(:organization, admin: @user)
      non_member = create(:verified_user)

      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      public_memex_project = create(:memex_project, public: true, owner: org)

      suggester = ProjectSuggester.new(viewer: non_member, context: repo, load_memex_projects: true)

      assert_empty suggester.organization_projects
    end

    test "does not include public projects if user is anonymous" do
      org = create(:organization, admin: @user)

      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      public_memex_project = create(:memex_project, public: true, owner: org)

      suggester = ProjectSuggester.new(viewer: nil, context: repo, load_memex_projects: true)

      assert_empty suggester.organization_projects
    end

    test "does not include any projects if user is anonymous" do
      org = create(:organization, admin: @user)

      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      public_memex_project = create(:memex_project, public: true, owner: org)

      suggester = ProjectSuggester.new(viewer: nil, context: repo, load_memex_projects: true)

      assert_same_elements [], suggester.organization_projects
    end

    test "includes memex projects that the viewer has organization wide write access" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      member = create(:verified_user)
      org.add_member(member)

      read_only_memex = create(:memex_project, owner: org)
      MemexHelpers::setup_organization_wide_access("project_reader", read_only_memex)

      write_memex = create(:memex_project, owner: org)

      suggester = ProjectSuggester.new(viewer: member, context: repo, load_memex_projects: true)

      assert_same_elements [write_memex], suggester.organization_projects
    end

    test "includes memex projects that the viewer has write access" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      member = create(:verified_user)
      org.add_member(member)

      memex = create(:memex_project, :with_writer, writer: member, owner: org)

      MemexHelpers::setup_organization_wide_access("project_reader", memex)

      suggester = ProjectSuggester.new(viewer: member, context: repo, load_memex_projects: true)

      assert_same_elements [memex], suggester.organization_projects
    end

    test "does not include memex project if the memex project is closed" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org, closed_at: Time.now)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [], suggester.organization_projects
    end

    test "sorts memex projects by title" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project1 = create(:memex_project, owner: org, title: "C")
      memex_project2 = create(:memex_project, owner: org, title: "B")
      memex_project3 = create(:memex_project, owner: org, title: "A")

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [memex_project3, memex_project2, memex_project1], suggester.organization_projects
    end

    test "combines projects and memex projects" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)

      project1 = create(:project, owner: org, name: "Project 1")
      project3 = create(:project, owner: org, name: "Project 3")
      project5 = create(:project, owner: org, name: "Project 5")
      memex_project2 = create(:memex_project, owner: org, title: "Project 2")
      memex_project4 = create(:memex_project, owner: org, title: "Project 4")
      memex_project6 = create(:memex_project, owner: org, title: "Project 6")

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [project1, memex_project2, project3, memex_project4, project5, memex_project6], suggester.organization_projects
    end

    test "can load memex project without a title" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)

      project = create(:project, owner: org, name: "Project 1")
      memex_project = create(:memex_project, owner: org, title: nil)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [project, memex_project], suggester.organization_projects
    end

    test "prefills the memex project owner" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project1 = create(:memex_project, owner: org)
      memex_project2 = create(:memex_project, owner: org)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      organization_projects = suggester.organization_projects

      assert_predicate organization_projects.first.association(:owner), :loaded?
      assert_predicate organization_projects.second.association(:owner), :loaded?
    end
  end

  context "#user_projects" do
    test "includes projects owned by the user" do
      repo = create(:repository, owner: @user)
      project = create(:project, owner: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [project], suggester.user_projects
    end

    test "includes memex projects owned by the user" do
      repo = create(:repository, owner: @user)
      memex_project = create(:memex_project, owner: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [memex_project], suggester.user_projects
    end

    test "does not include projects owned by the org" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      project = create(:project, owner: org)
      memex_project = create(:memex_project, owner: org)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_empty suggester.user_projects
    end

    test "does not include memex project if the memex project is closed" do
      repo = create(:repository, owner: @user)
      memex_project = create(:memex_project, owner: @user, closed_at: Time.now)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_same_elements [], suggester.user_projects
    end

    test "includes memex projects for collaborator with write access" do
      repo = create(:repository, owner: @user)
      collaborator = create(:verified_user)
      memex_project = create(:memex_project, :with_writer, writer: collaborator, owner: @user)

      suggester = ProjectSuggester.new(viewer: collaborator, context: repo, load_memex_projects: true)

      assert_same_elements [memex_project], suggester.user_projects
    end

    test "includes projects owned by another user that the viewer has write access to" do
      viewer = create(:user)
      repo = create(:repository, owner: @user)
      project = create(:project, owner: @user)

      repo.add_member(viewer)
      project.update_user_permission(viewer, :write)

      suggester = ProjectSuggester.new(viewer: viewer, context: repo)

      assert_same_elements [project], suggester.user_projects
    end

    test "includes projects owned by another user that the viewer has read access to, if querying readable" do
      viewer = create(:user)
      repo = create(:repository, owner: @user)
      project = create(:project, owner: @user)

      repo.add_member(viewer)
      project.update_user_permission(viewer, :read)

      suggester = ProjectSuggester.new(viewer: viewer, context: repo)

      assert_same_elements [project], suggester.user_projects(min_permission_level: "read")
    end

    test "prioritizes linked repositories" do
      repo = create(:repository, owner: @user)

      unlinked_project_1 = create(:project, owner: @user, name: "Project A")

      # Create the linked project between the two unlinked ones, so that it
      # wouldn't naturally end up as the first project no matter what
      # date-based sort was used.
      linked_project = create(:project, owner: @user, name: "Project B")
      linked_project.link_repository(repo, @user)

      unlinked_project_2 = create(:project, owner: @user, name: "Project C")

      suggester = ProjectSuggester.new(viewer: @user, context: repo)
      projects = suggester.user_projects

      # Make sure all the projects are there, regardless of order.
      assert_same_elements [linked_project, unlinked_project_1, unlinked_project_2], projects

      # Make sure the linked project comes first.
      assert_equal linked_project, projects.first
    end

    test "does not include any projects if the viewer is logged out" do
      repo = create(:repository, owner: @user)
      create(:project, owner: @user)
      create(:memex_project, owner: @user)

      suggester = ProjectSuggester.new(viewer: nil, context: repo, load_memex_projects: true)

      assert_empty suggester.user_projects
    end

    test "does not include closed projects" do
      repo = create(:repository, owner: @user)
      project = create(:project, owner: @user, closed_at: Time.now)
      memex_project = create(:memex_project, owner: @user, closed_at: Time.now)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_predicate project, :closed?
      assert_predicate memex_project, :closed?
      assert_empty suggester.user_projects
    end

    test "prefills the project owner" do
      repo = create(:repository, owner: @user)
      project = create(:project, owner: @user)
      memex_project = create(:memex_project, owner: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_predicate suggester.user_projects[0].association(:owner), :loaded?
      assert_predicate suggester.user_projects[1].association(:owner), :loaded?
    end
  end

  context "#recent_projects" do
    test "includes projects the user has added cards to recently" do
      org = create(:organization, admin: @user)
      recent_org_project = create(:project, owner: org)

      repo = create(:repository, owner: org)
      recent_repo_project = create(:project, owner: repo)

      create(:project_card, project: recent_repo_project, creator: @user)
      create(:project_card, project: recent_org_project, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [recent_repo_project, recent_org_project], suggester.recent_projects
    end

    test "includes user projects the user has added cards to recently" do
      repo = create(:repository, owner: @user)
      recent_repo_project = create(:project, owner: repo)
      recent_user_project = create(:project, owner: @user)

      create(:project_card, project: recent_repo_project, creator: @user)
      create(:project_card, project: recent_user_project, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [recent_repo_project, recent_user_project], suggester.recent_projects
    end

    test "includes another user's projects the user has added cards to recently" do
      other_user = create(:user)
      repo = create(:repository, owner: @user)
      recent_project = create(:project, owner: @user)

      repo.add_member(other_user)
      recent_project.update_user_permission(other_user, :write)

      create(:project_card, project: recent_project, creator: other_user)

      suggester = ProjectSuggester.new(viewer: other_user, context: repo)

      assert_same_elements [recent_project], suggester.recent_projects
    end

    test "includes another user's projects the user has added cards to recently, if querying readable" do
      other_user = create(:user)
      repo = create(:repository, owner: @user)
      recent_project = create(:project, owner: @user)

      repo.add_member(other_user)
      recent_project.update_user_permission(other_user, :write)
      create(:project_card, project: recent_project, creator: other_user)

      recent_project.update_user_permission(other_user, :read)

      suggester = ProjectSuggester.new(viewer: other_user, context: repo)

      assert_same_elements [recent_project], suggester.recent_projects(min_permission_level: "read")
    end

    test "sorts by card updated timestamp" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)

      Timecop.freeze(10.minutes.ago) do
        @recent_project = create(:project, owner: org, name: "recent")
        create(:project_card, project: @recent_project, creator: @user)
        @most_recent = create(:project_card, project: @recent_project, creator: @user)
      end

      Timecop.freeze(5.minutes.ago) do
        @oldest_project = create(:project, owner: org, name: "oldest")
        create(:project_card, project: @oldest_project, creator: @user)
      end

      # At this point the cards are in order of updated like this
      # Card 10 mins ago - recent_project
      # Card 5 mins ago - oldest_project
      # Card most_recent - recent_project
      @most_recent.note = "test"
      @most_recent.save!

      # The suggester should now return a list of projects that are unique
      #    and are ordered by which as the most recently updated card
      suggester = ProjectSuggester.new(viewer: @user, context: repo)
      assert_equal [@recent_project, @oldest_project], suggester.recent_projects
    end

    test "does not include repository projects the user no longer has access to" do
      repo = create(:repository)
      repo.add_member(@user)
      recent_repo_project = create(:project, owner: repo)

      create(:project_card, project: recent_repo_project, creator: @user)
      repo.remove_member(@user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_empty suggester.recent_projects
    end

    test "does include repository projects the user has access read access, if querying readable" do
      repo = create(:repository)
      repo.add_member(@user)
      recent_repo_project = create(:project, owner: repo)

      create(:project_card, project: recent_repo_project, creator: @user)
      repo.remove_member(@user)
      repo.add_member(@user, action: :read)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [recent_repo_project], suggester.recent_projects(min_permission_level: "read")
    end

    test "does not include organization projects the user no longer has access to" do
      org = create(:organization)
      org.add_member(@user)

      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      repo.add_member(@user)

      visible_org_project = create(:project, owner: org)
      visible_org_project.update_org_permission(:write)
      create(:project_card, project: visible_org_project, content: issue, creator: @user)

      hidden_org_project = create(:project, owner: org)
      hidden_org_project.update_org_permission(nil)
      create(:project_card, project: hidden_org_project, content: issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)
      assert_same_elements [visible_org_project], suggester.recent_projects
    end

    test "does include organization projects the user has read access to, if querying readable" do
      org = create(:organization)
      org.add_member(@user)

      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)
      repo.add_member(@user)

      writable_org_project = create(:project, owner: org)
      writable_org_project.update_org_permission(:write)
      create(:project_card, project: writable_org_project, content: issue, creator: @user)

      readable_org_project = create(:project, owner: org)
      readable_org_project.update_org_permission(:read)
      create(:project_card, project: readable_org_project, content: issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)
      assert_same_elements [writable_org_project, readable_org_project], suggester.recent_projects(min_permission_level: "read")
    end

    test "does not include projects outside the context" do
      personal_repo = create(:repository, owner: @user)
      personal_repo_project = create(:project, owner: personal_repo)
      # This card should not be in the results
      create(:project_card, project: personal_repo_project, creator: @user)

      org = create(:organization, admin: @user)
      recent_org_project = create(:project, owner: org, name: "Recent Org Project")

      repo = create(:repository, owner: org)
      recent_repo_project = create(:project, owner: repo, name: "Recent Repo Project")

      create(:project_card, project: recent_repo_project, creator: @user)
      create(:project_card, project: recent_org_project, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_same_elements [recent_repo_project, recent_org_project], suggester.recent_projects
    end

    test "does not include any projects if the viewer is logged out" do
      repo = create(:repository)
      recent_repo_project = create(:project, owner: repo)
      create(:project_card, project: recent_repo_project)

      suggester = ProjectSuggester.new(viewer: nil, context: repo)

      assert_empty suggester.recent_projects
    end

    test "does not include closed projects" do
      org = create(:organization)
      org.add_member @user
      repo = create(:repository, owner: org)

      repo_project = create(:project, owner: org, closed_at: Time.now)
      org_project = create(:project, owner: repo, closed_at: Time.now)
      create(:project_card, project: repo_project, creator: @user)
      create(:project_card, project: org_project, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      assert_predicate repo_project, :closed?
      assert_predicate org_project, :closed?
      assert_empty suggester.recent_projects
    end

    test "does not include recent classic projects if load_classic_projects is false" do
      org = create(:organization, admin: @user)

      repo = create(:repository, owner: org)
      recent_repo_project = create(:project, owner: repo)

      create(:project_card, project: recent_repo_project, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_classic_projects: false)

      assert_same_elements [], suggester.recent_projects
    end

    test "prefills the project owner" do
      org = create(:organization, admin: @user)
      recent_org_project = create(:project, owner: org)

      repo = create(:repository, owner: org)
      recent_repo_project = create(:project, owner: repo)

      create(:project_card, project: recent_repo_project, creator: @user)
      create(:project_card, project: recent_org_project, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo)

      recent_projects = suggester.recent_projects
      assert_predicate recent_projects.first.association(:owner), :loaded?
      assert_predicate recent_projects.second.association(:owner), :loaded?
    end
  end

  context "#recent_memex_projects" do
    test "does not include org memex project if the user has not added issue to recently" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)

      other_user = create(:user, :verified)
      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: other_user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [], suggester.recent_projects
    end

    test "does not include user memex project if the user has not added issue to recently" do
      repo = create(:repository, owner: @user)
      memex_project = create(:memex_project, owner: @user)

      other_user = create(:user, :verified)
      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: other_user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [], suggester.recent_projects
    end

    test "does not include org memex project if the project is closed" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org, closed_at: Time.now)

      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [], suggester.recent_projects
    end

    test "returns memex projects that are templates when requested" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org, closed_at: Time.now)
      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)
      memex_project_with_template = create(:memex_project, owner: org)
      memex_template = create(:memex_template, memex_project: memex_project_with_template)
      create(:memex_project_item, memex_project: memex_project_with_template, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, only_memex_templates: true, load_memex_projects: true)

      assert_equal [memex_project_with_template], suggester.recent_projects
    end

    test "returns both memex projects and templates when only_memex_templates kwarg is false" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)
      memex_project_with_template = create(:memex_project, owner: org)
      memex_template = create(:memex_template, memex_project: memex_project_with_template)
      create(:memex_project_item, memex_project: memex_project_with_template, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, only_memex_templates: false, load_memex_projects: true)

      assert_same_elements [memex_project, memex_project_with_template], suggester.recent_projects
    end

    test "returns both memex projects and templates when only_memex_templates kwarg is not provided" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)
      memex_project_with_template = create(:memex_project, owner: org)
      memex_template = create(:memex_template, memex_project: memex_project_with_template)
      create(:memex_project_item, memex_project: memex_project_with_template, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, only_memex_templates: nil, load_memex_projects: true)

      assert_same_elements [memex_project, memex_project_with_template], suggester.recent_projects
    end

    test "does not include user memex project if the project is closed" do
      repo = create(:repository, owner: @user)
      memex_project = create(:memex_project, owner: @user, closed_at: Time.now)

      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [], suggester.recent_projects
    end

    test "does not include user memex project if the project is deleted" do
      repo = create(:repository, owner: @user)
      memex_project = create(:memex_project, owner: @user, deleted_at: Time.now)

      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [], suggester.recent_projects
    end

    test "does not include org memex project when the option is disabled" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)

      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: false)

      assert_equal [], suggester.recent_projects
    end

    test "does not include user memex project when the option is disabled" do
      repo = create(:repository, owner: @user)
      memex_project = create(:memex_project, owner: @user)

      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: false)

      assert_equal [], suggester.recent_projects
    end

    test "does not include org memex project from other orgs" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)
      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      other_org = create(:organization, admin: @user)
      other_memex_project = create(:memex_project, owner: other_org)
      create(:memex_project_item, memex_project: other_memex_project, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [memex_project], suggester.recent_projects
    end

    test "does not include user memex project from other users" do
      repo = create(:repository, owner: @user)
      memex_project = create(:memex_project, owner: @user)
      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      other_user = create(:verified_user)
      other_memex_project = create(:memex_project, owner: other_user)
      create(:memex_project_item, memex_project: other_memex_project, content: @issue, creator: other_user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [memex_project], suggester.recent_projects
    end

    test "includes org memex project the user has added issue to recently" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project = create(:memex_project, owner: org)

      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [memex_project], suggester.recent_projects
    end

    test "includes user memex project the user has added issue to recently" do
      repo = create(:repository, owner: @user)
      memex_project = create(:memex_project, owner: @user)

      create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [memex_project], suggester.recent_projects
    end

    test "sorts org memex projects the user has added issue to by item updated timestamp" do
      org = create(:organization, admin: @user)
      other_user = create(:verified_user)
      org.add_member(other_user, action: :admin)
      repo = create(:repository, owner: org)
      memex_project1 = create(:memex_project, owner: org)
      memex_project2 = create(:memex_project, owner: org)
      memex_project3 = create(:memex_project, owner: org)

      Timecop.freeze(15.minutes.ago) do
        create(:memex_project_item, memex_project: memex_project1, content: @issue, creator: other_user)
      end
      Timecop.freeze(10.minutes.ago) do
        create(:memex_project_item, memex_project: memex_project2, content: @issue, creator: @user)
      end
      Timecop.freeze(5.minutes.ago) do
        create(:memex_project_item, memex_project: memex_project3, content: @issue, creator: @user)
      end

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [memex_project3, memex_project2], suggester.recent_projects
    end

    test "sorts user memex projects the user has added issue to by item updated timestamp" do
      repo = create(:repository, owner: @user)
      memex_project1 = create(:memex_project, owner: @user)
      memex_project2 = create(:memex_project, owner: @user)
      memex_project3 = create(:memex_project, owner: @user)

      Timecop.freeze(15.minutes.ago) do
        create(:memex_project_item, memex_project: memex_project1, content: @issue, creator: @user)
      end
      Timecop.freeze(10.minutes.ago) do
        create(:memex_project_item, memex_project: memex_project2, content: @issue, creator: @user)
      end
      Timecop.freeze(5.minutes.ago) do
        create(:memex_project_item, memex_project: memex_project3, content: @issue, creator: @user)
      end

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal [memex_project3, memex_project2, memex_project1], suggester.recent_projects
    end

    test "limits to the most 10 recent memex projects" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)

      memex_projects = []
      30.times do |i|
        Timecop.freeze(i.minutes.ago) do
          memex_project = create(:memex_project, owner: org)
          memex_projects << memex_project
          create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)
        end
      end

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal 10, suggester.recent_projects.size
      assert_equal memex_projects.first(10), suggester.recent_projects
    end

    test "limits to the most 10 recent user memex projects" do
      repo = create(:repository, owner: @user)

      memex_projects = []
      30.times do |i|
        Timecop.freeze(i.minutes.ago) do
          memex_project = create(:memex_project, owner: @user)
          memex_projects << memex_project
          create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)
        end
      end

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal 10, suggester.recent_projects.size
      assert_equal memex_projects.first(10), suggester.recent_projects
    end

    test "combines projects and org memex projects" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)

      projects = []
      memex_projects = []
      20.times do |i|
        Timecop.freeze(i.minutes.ago) do
          if i.even?
            project = create(:project, owner: org)
            projects << project
            create(:project_card, project: project, creator: @user)
          else
            memex_project = create(:memex_project, owner: org)
            memex_projects << memex_project
            create(:memex_project_item, memex_project: memex_project, content: issue, creator: @user)
          end
        end
      end

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal 20, suggester.recent_projects.size
      assert_equal (memex_projects + projects), suggester.recent_projects
    end

    test "combines projects and user memex projects" do
      repo = create(:repository, owner: @user)

      projects = []
      memex_projects = []
      20.times do |i|
        Timecop.freeze(i.minutes.ago) do
          if i.even?
            project = create(:project, owner: @user)
            projects << project
            create(:project_card, project: project, creator: @user)
          else
            memex_project = create(:memex_project, owner: @user)
            memex_projects << memex_project
            create(:memex_project_item, memex_project: memex_project, content: @issue, creator: @user)
          end
        end
      end

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal 20, suggester.recent_projects.size
      assert_equal (memex_projects + projects), suggester.recent_projects
    end

    test "returns org memexes linked to the org repository alongside recent org projects" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)

      memex_projects = []

      2.times do
        memex_projects << create(:memex_project, owner: org)
      end

      create(:memex_project_item, memex_project: memex_projects.first, content: @issue, creator: @user)

      create(:memex_project_link, source: repo, memex_project: memex_projects.last)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal memex_projects, suggester.recent_projects(include_repo_linked: true)
    end

    test "returns org memexes linked to the org repository alongside recent org projects (with deduplication)" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)

      memex_projects = []

      2.times do
        project = create(:memex_project, owner: org)
        create(:memex_project_link, source: repo, memex_project: project)
        memex_projects << project
      end

      create(:memex_project_item, memex_project: memex_projects.first, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal memex_projects, suggester.recent_projects(include_repo_linked: true)
    end

    test "returns user memexes linked to the user repository alongside recent user projects" do
      repo = create(:repository, owner: @user)
      issue = create(:issue, repository: repo)

      memex_projects = []

      2.times do
        memex_projects << create(:memex_project, owner: @user)
      end

      create(:memex_project_item, memex_project: memex_projects.first, content: issue, creator: @user)

      create(:memex_project_link, source: repo, memex_project: memex_projects.last)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      assert_equal memex_projects, suggester.recent_projects(include_repo_linked: true)
    end

    test "returns user memexes linked to the user repository alongside recent user projects, with the linked repos ordered by updated at date" do
      repo = create(:repository, owner: @user)
      issue = create(:issue, repository: repo)

      memex_projects = T.let([], T::Array[MemexProject])

      4.times do |i|
        Timecop.freeze((4 - i).hours.ago) do
          memex_projects << create(:memex_project, owner: @user, title: "memex-#{i}")
          next if i == 0

          create(:memex_project_link, source: repo, memex_project: memex_projects[i])
        end
      end

      create(:memex_project_item, memex_project: memex_projects.first, content: issue, creator: @user)

      Timecop.freeze(1.day.from_now) do
        T.must(memex_projects[2]).touch

        suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

        assert_equal [
          memex_projects[0],
          memex_projects[2],
          memex_projects[3],
          memex_projects[1]
        ], suggester.recent_projects(include_repo_linked: true)
      end
    end

    test "displays only Memex projects" do
      org = create(:organization, admin: @user)

      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo)

      member = create(:verified_user)
      org.add_member(member)

      memex_projects = []
      10.times do |i|
        Timecop.freeze(i.minutes.ago) do
          memex_project = create(:memex_project, owner: org)
          if i.even?
            # members have write permissions by default, setting it to read
            MemexHelpers::setup_organization_wide_access("project_reader", memex_project)
          else
            memex_projects << memex_project
          end

          create(:memex_project_item, memex_project: memex_project, content: issue, creator: member)
        end
      end

      suggester = ProjectSuggester.new(viewer: member, context: repo, load_memex_projects: true)

      assert_equal 5, suggester.recent_projects.size
      assert_equal memex_projects, suggester.recent_projects
    end

    test "prefills the org memex project owner" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project1 = create(:memex_project, owner: org)
      memex_project2 = create(:memex_project, owner: org)

      create(:memex_project_item, memex_project: memex_project1, content: @issue, creator: @user)
      create(:memex_project_item, memex_project: memex_project2, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      recent_projects = suggester.recent_projects

      assert_predicate recent_projects.first.association(:owner), :loaded?
      assert_predicate recent_projects.second.association(:owner), :loaded?
    end

    test "prefills the user memex project owner" do
      repo = create(:repository, owner: @user)
      memex_project1 = create(:memex_project, owner: @user)
      memex_project2 = create(:memex_project, owner: @user)

      create(:memex_project_item, memex_project: memex_project1, content: @issue, creator: @user)
      create(:memex_project_item, memex_project: memex_project2, content: @issue, creator: @user)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      recent_projects = suggester.recent_projects

      assert_predicate recent_projects.first.association(:owner), :loaded?
      assert_predicate recent_projects.second.association(:owner), :loaded?
    end

    test "only returns memexes when load_classic_projects is false for organizations" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: org)
      memex_project1 = create(:memex_project, owner: org)
      memex_project2 = create(:memex_project, owner: org)
      memex_project3 = create(:memex_project, owner: @user)
      project = create(:project, owner: org, closed_at: Time.now)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true, load_classic_projects: false)

      projects = suggester.organization_projects

      # Make sure all the projects are there, regardless of order.
      assert_same_elements [memex_project1, memex_project2], projects
      refute projects.include?(project)
      refute projects.include?(memex_project3)
    end

    test "only returns memexes when load_classic_projects is false for users" do
      org = create(:organization, admin: @user)
      repo = create(:repository, owner: @user)

      memex_project1 = create(:memex_project, owner: @user)
      memex_project2 = create(:memex_project, owner: @user)
      memex_project3 = create(:memex_project, owner: org)
      project = create(:project, owner: @user, closed_at: Time.now)

      suggester = ProjectSuggester.new(viewer: @user, context: repo, load_memex_projects: true)

      projects = suggester.user_projects

      # Make sure all the projects are there, regardless of order.
      assert_same_elements [memex_project1, memex_project2], projects
      refute projects.include?(project)
      refute projects.include?(memex_project3)
    end

    test "does not include any recent projects if the viewer is logged out" do
      repo = create(:repository, owner: @user)
      create(:project, owner: @user)
      create(:memex_project, owner: @user)

      suggester = ProjectSuggester.new(viewer: nil, context: repo, load_memex_projects: true)

      assert_empty suggester.async_recent_memex_projects.sync
    end
  end
end
