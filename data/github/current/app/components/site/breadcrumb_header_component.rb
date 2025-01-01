# typed: true
# frozen_string_literal: true

# This component renders top-level, breadcrumb-style navigation in the site header
#
# To use this, provide breadcrumb info to the `page_info` helper in your views
# (much like setting the page title or other metadata).

module Site
  class BreadcrumbHeaderComponent < ApplicationComponent
    VALID_OBJECT_TYPES = [
      Discussion,
      Issue,
      MemexProject,
      Organization,
      Project,
      PullRequest,
      Registry::Package,
      Repository,
      Team,
      Topic,
      User,
      ::Actions::WorkflowRun,
      ::Actions::WorkflowRunExecution,
    ]

    attr_reader :title, :provided_owner, :parent_page

    def initialize(object: nil, title: nil, owner: nil)
      @object = object
      @title = title

      if owner.is_a?(Symbol)
        @provided_owner = nil
        @parent_page = owner
      else
        @provided_owner = owner
      end
    end

    private

    def breadcrumbs
      crumbs = [
        parent_page_breadcrumb,
        owner_breadcrumb,
        repository_breadcrumb,
        object_breadcrumbs,
      ]

      if title.present?
        crumbs << {
          text: title,
          test_selector: "breadcrumb-title"
        }
      end

      crumbs.flatten!
      crumbs.compact!

      # apply default text styles if they haven't been customized
      crumbs.map do |item|
        item[:path] = item[:path] if item[:path].present?

        item[:text_style] ||= if item == crumbs.last
          "text-bold Header-current-page js-context-region-label"
        else
          "text-normal"
        end

        item
      end
    end

    def parent_page_breadcrumb
      return nil unless parent_page.present?
      parent_pages = {}

      # meta info about root pages in the breadcrumb trail that aren't "owners" (Users/Orgs)
      unless GitHub.multi_tenant_enterprise?
        parent_pages = {
          explore: {
            text: "Explore",
            path: explore_path
          }
        }
      end

      unless GitHub.enterprise?
        parent_pages[:marketplace] = {
          text: "Marketplace",
          path: marketplace_path
        }
      end

      parent_pages[parent_page].merge({ test_selector: "parent-page" })
    end

    def repository_breadcrumb
      return nil unless repo.present?
      return nil if org_level_discussion?(owner)

      {
        text: repo.name,
        path: repository_path(repo),
        octicon: repo.private? ? "lock" : nil,
        test_selector: "repo-name"
      }
    end

    def owner_breadcrumb
      return nil unless owner.present?

      {
        text: owner.display_login,
        path: user_path(owner),
        test_selector: "owner-name"
      }
    end

    def team_breadcrumbs
      team_breadcrumbs = []

      team_breadcrumbs << {
        text: "Teams",
        path: teams_path(owner)
      }

      if grand_parent_team.present?
        team_breadcrumbs << { text: "..." }
      end

      if parent_team.present?
        team_breadcrumbs << {
          text: parent_team.name,
          path: team_path(parent_team)
        }
      end

      if new_team?
        team_breadcrumbs << { text: "New team", text_style: "text-normal" }
      else
        team_breadcrumbs << {
          text: @object.name,
          octicon: "people",
          test_selector: "team-name"
        }
      end
    end

    def project_breadcrumbs
      path_for_index = if @object.owner.is_a?(Organization)
        org_projects_path(owner.display_login, type: "classic")
      elsif @object.owner.is_a?(User)
        user_projects_path(owner.display_login, type: "classic")
      elsif @object.owner.is_a?(Repository)
        repo_projects_path(owner, @object.owner, type: "classic")
      end

      project_crumbs = []

      project_crumbs << {
        text: "Projects",
        path: path_for_index,
        test_selector: "project-path"
      }

      if @object.new_record?
        project_crumbs << { text: "New project" }
      else
        project_crumb = {
          text: @object.name,
          octicon: "project",
          test_selector: "project-name"
        }

        project_crumb[:path] = project_path(@object) if title.present?

        project_crumbs << project_crumb
      end
    end

    def object_breadcrumbs
      if issue?
        [
          {
            text: "Issues",
            path: issues_path(owner, @object.repository)
          },
          {
            text: "##{@object.number}"
          }
        ]
      elsif pull?
        [
          {
            text: "Pull requests",
            path: pull_requests_path(owner, @object.repository)
          },
          {
            text: "##{@object.number}"
          }
        ]
      elsif discussion?
        [
          {
            text: "Discussions",
            path: org_level_discussion?(owner) ? org_discussions_path(owner) : discussions_path(owner, @object.repository),
            test_selector: "discussion-path"
          },
          {
            text: "##{@object.number}",
            test_selector: "discussion-number"
          }
        ]
      elsif package?
        [
          {
            text: "Packages",
            path: org_packages_path(owner)
          },
          {
            text: @object.name,
            octicon: "package",
            test_selector: "package-name"
          }
        ]
      elsif team?
        team_breadcrumbs
      elsif project?
        project_breadcrumbs
      elsif org_person?
        [
          {
            text: "People",
            path: org_people_path(owner)
          },
          {
            text: @object.display_login,
            octicon: "person",
            test_selector: "person-name"
          }
        ]
      elsif memex?
        [
          {
            text: "Projects",
            path:  owner.organization? ? org_projects_path(owner) : user_projects_path(owner),
            test_selector: "project-path"
          },
          {
            text: @object.new_record? ? "New project" : @object.title,
            octicon: "table",
            test_selector: "project-name"
          }
        ]
      elsif topic?
        [
          {
            text: "Topics",
            path: topics_path
          },
          {
            text: @object.safe_display_name
          }
        ]
      elsif workflow_run?
        [
          {
            text: "Actions",
            path: actions_path(owner, repo)
          },
          {
            text: "#{@object.workflow_name} ##{@object.run_number}"
          }
        ]
      elsif workflow_run_execution?
        [
          {
            text: "Actions",
            path: actions_path(owner, repo)
          },
          {
            text: "#{@object.workflow_run.workflow_name} ##{@object.workflow_run.run_number}",
            path: workflow_run_path(owner, repo, @object.workflow_run)
          },
          {
            text: "Attempt ##{@object.attempt}"
          }
        ]
      end
    end

    def render?
      (@object.present? && VALID_OBJECT_TYPES.include?(@object.class)) ||
      @title.present?
    end

    def user_or_org?
      @object.is_a?(User) || @object.is_a?(Organization)
    end

    def repository?
      @object.is_a?(Repository)
    end

    def team?
      @object.is_a?(Team)
    end

    def project?
      @object.is_a?(Project)
    end

    def org_person?
      @object.is_a?(User) && provided_owner&.organization?
    end

    def new_team?
      team? && @object.new_record?
    end

    def memex?
      @object.is_a?(MemexProject)
    end

    def parent_team
      @object.parent_team if team? && !new_team?
    end

    def grand_parent_team
      parent_team&.parent_team
    end

    def package?
      @object.is_a?(Registry::Package)
    end

    def issue?
      @object.is_a?(Issue)
    end

    def pull?
      @object.is_a?(PullRequest)
    end

    def discussion?
      @object.is_a?(Discussion)
    end

    def org_level_discussion?(owner)
      return false unless GitHub.discussions_available_on_platform?
      params.has_key?(:org) && owner.is_a?(Organization) && owner.discussion_repository.present?
    end

    def topic?
      @object.is_a?(Topic)
    end

    def workflow_run?
      @object.is_a?(::Actions::WorkflowRun)
    end

    def workflow_run_execution?
      @object.is_a?(::Actions::WorkflowRunExecution)
    end

    def repo
      if repository?
        @object
      elsif issue? || pull? || discussion? || workflow_run? || workflow_run_execution?
        @object.repository
      elsif @object.respond_to?(:owner) && @object.owner.is_a?(Repository)
        @object.owner
      else
        nil
      end
    end

    def owner
      # if an owner is explicitly provided, use that
      return provided_owner if provided_owner.present?

      # otherwise we can try to infer it based on type
      if repository? || memex?
        @object.owner
      elsif issue? || pull? || discussion? || workflow_run? || workflow_run_execution?
        @object.repository.owner
      elsif package?
        @object.repository.owner
      elsif team?
        @object.organization
      elsif user_or_org?
        @object
      elsif project?
        if @object.owner.is_a?(Repository)
          @object.owner.owner
        else
          @object.owner
        end
      else
        nil
      end
    end
  end
end
