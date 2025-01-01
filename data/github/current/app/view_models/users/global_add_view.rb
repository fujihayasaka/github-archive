# typed: true
# frozen_string_literal: true

class Users::GlobalAddView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :repository, :current_user

  # Public: Show organization link?
  #
  # Returns true or false.
  def show_org_links?
    return @org_links if defined?(@org_links)
    @org_links = organization && !organization.new_record? && organization.adminable_by?(current_user)
  end

  # Public: Show the import repository link?
  #
  # Returns true or false.
  def show_repository_import_link?
    return @repository_import_link if defined?(@repository_import_link)
    @repository_import_link = GitHub.porter_available?
  end

  # Public: Returns the organization instance
  #
  def organization
    return @org if defined?(@org)
    @org = attributes[:organization] || repository_organization
  end

  private

  def repository_organization
    return @org_repo if defined?(@org_repo)
    @org_repo = repository && repository.owner.organization? && repository.owner
  end
end
