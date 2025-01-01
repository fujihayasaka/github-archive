# typed: true
# frozen_string_literal: true

class Repository
  class Updater
    attr_reader :error, :actor, :repository, :name, :template, :has_issues, :description,
                :homepage, :has_wiki, :has_projects, :has_discussions, :has_sponsorships

    # Public: Update a repository with various attributes if the given user is allowed.
    #
    # repository - a Repository to update
    # actor - the currently authenticated User
    # attrs - a Hash with any of the following keys (omit/pass nil to leave unchanged):
    #         :name - String name of repository
    #         :template - Boolean whether the repo should be marked as a template
    #         :has_issues - Boolean whether to enable issues on the repo
    #         :description - String description of the repository; pass a blank string to wipe
    #                        existing description
    #         :homepage - String URL to a website about the repository; pass a blank string to wipe
    #                     existing URL
    #         :has_wiki - Boolean whether to enable wikis on the repo
    #         :has_projects - Boolean whether to enable projects on the repo
    #         :has_discussions - Boolean whether to enable discussions on the repo
    #         :has_sponsorships - Boolean whether to enable sponsorships on the repo
    def initialize(repository, actor:, **attrs)
      @repository = repository
      @actor = actor
      @error = nil
      @name = attrs[:name]
      @template = attrs[:template]
      @has_issues = attrs[:has_issues]
      @description = attrs[:description]
      @homepage = attrs[:homepage]
      @has_wiki = attrs[:has_wiki]
      @has_projects = attrs[:has_projects]
      @has_discussions = attrs[:has_discussions]
      @has_sponsorships = attrs[:has_sponsorships]
    end

    # Public: Apply the specified changes to the repository.
    #
    # Sets the error property on failure.
    #
    # Returns true on success, false on failure.
    def update
      unless repository.writable?
        @error = "Repository #{repository.name_with_owner} cannot be edited at this time."
        return false
      end

      unless repository.resources.administration.writable_by?(actor)
        @error = "#{actor} does not have permission to update #{repository.name_with_owner}."
        return false
      end

      if !name.nil? && repository.blocks_repository_rename?(actor)
        @error = "Name can't be changed on a repository protected by a ruleset."
        return false
      end

      repository.name = name unless name.nil?
      repository.template = template unless template.nil?
      repository.has_issues = has_issues unless has_issues.nil?

      has_new_description = !description.nil?
      has_new_homepage = !homepage.nil?
      if has_new_description || has_new_homepage
        if repository.can_edit_repo_metadata?(actor)
          repository.description = description.presence if has_new_description
          repository.homepage = homepage.presence if has_new_homepage
        else
          @error = "#{actor} does not have permission to edit metadata on " \
                   "#{repository.name_with_owner}."
          return false
        end
      end

      if !has_wiki.nil?
        if repository.can_toggle_wiki?(actor)
          repository.has_wiki = has_wiki
        else
          @error = "#{actor} does not have permission to toggle wikis on " \
                   "#{repository.name_with_owner}."
          return false
        end
      end

      unless has_projects.nil?
        begin
          if has_projects
            repository.enable_repository_projects(actor: actor)
          else
            repository.disable_repository_projects(actor: actor)
          end
        rescue Repository::ProjectsDependency::CannotEnableProjectsError
          cannot_enable_projects = true
        end

        begin
          if has_projects
            repository.enable_repository_memex_projects(actor: actor)
          else
            repository.disable_repository_memex_projects(actor: actor)
          end
        rescue Repository::MemexesDependency::CannotEnableProjectsError
          cannot_enable_memex_projects = true
        end

        if cannot_enable_projects && cannot_enable_memex_projects
          @error = "Projects cannot be enabled when the owning organization has projects disabled."
          return false
        end
      end

      unless has_discussions.nil?
        if repository.can_toggle_discussions_setting?(actor)
          if has_discussions
            repository.turn_on_discussions(actor: actor)
          else
            repository.turn_off_discussions(actor: actor)
          end
        else
          @error = "#{actor} does not have permission to toggle discussions on " \
                   "#{repository.name_with_owner}."
          return false
        end
      end

      unless has_sponsorships.nil?
        if repository.can_enable_repository_funding_links?
          if has_sponsorships
            repository.enable_repository_funding_links(actor: actor)
          else
            repository.disable_repository_funding_links(actor: actor)
          end
        else
          @error = "#{actor} does not have permission to toggle sponsorships on " \
                   "#{repository.name_with_owner}."
          return false
        end
      end

      if repository.save
        repository.invalidate_nwo_cache(Repositories::Cache::InvalidateOn::GraphqlMutation)
        true
      else
        @error = repository.errors.full_messages.to_sentence.presence
        false
      end
    end
  end
end
