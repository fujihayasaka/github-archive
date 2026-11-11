# typed: true
# frozen_string_literal: true

class Stafftools::Projects::ShowView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :project, :migrated_memex

  # Public: All suitable owners for this project.
  #
  # If `project` is an org/user project, this will return all repositories that
  # have issues or PR cards.
  # If all cards are Notes or the board is empty, all of the org/user repos will
  # be listed.
  #
  # If `project` belongs to a repo, this will return the repo's owning org/user
  #
  def suitable_owners
    @suitable_owners ||= begin
      if owner.is_a?(Repository)
        [["@#{owner.owner.login}", owner.owner_id]]
      elsif owner.is_a?(User)
        repos = project.cards.for_content_type("Issue").includes(:content).map(&:content).map(&:repository_id).uniq # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        if repos.any?
          Repository.where(id: repos).pluck(:name, :id)
        else
          owner.repositories.with_issues_enabled.pluck(:name, :id)
        end
      end
    end

    @suitable_owners ||= []
  end

  # Public: What owner_type can we transfer this project to?
  def suitable_owner_type
    # User or Org projects can be transferred to repositories
    return "Repository" if project.owner.is_a?(User)

    # Otherwise, it can be transferred to the repo owner
    if project.owner.owner.is_a?(Organization)
      "Organization"
    else
      "User"
    end
  end

  # Public: Does this project only have one suitable owner?
  #
  # Returns true if so, false if not.
  #
  def one_suitable_owner?
    suitable_owners.size == 1
  end

  # Public: Get the object of the one suitable owner.
  #
  # If there is only one suitable owner, returns the User, Organization or
  # Repository object representing the suitable owner.
  # If there are multiple suitable owners, returns nil.
  #
  def suitable_owner_object
    return nil unless one_suitable_owner?

    suitable_owner_type.constantize.find_by(id: suitable_owners.first[1])
  end

  # Public: Will the creator of this project be added as an admin after transferring?
  #
  # Returns a boolean.
  # The actual check for adding the creator is in Organiziation#change_owner_of!,
  # this is just a test for the view.
  #
  def will_automatically_add_creator_to_project?
    return nil unless suitable_owner_object.respond_to?(:member?)

    suitable_owner_object.member?(project.creator)
  end

  def issue_cards_size
    project.cards.issues.size
  end

  def pull_cards_size
    project.cards.pulls.size
  end

  private

  # Private: The project's owner
  def owner
    project.owner
  end
end
