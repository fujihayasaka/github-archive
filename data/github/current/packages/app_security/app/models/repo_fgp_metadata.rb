# typed: true
# frozen_string_literal: true

class RepoFgpMetadata
  attr_reader :label, :category, :description

  # Fine Grained Permission metadata
  def initialize(fgp)
    @label = fgp
    @category = RepoFgpMetadata.category_for(fgp)
    @description = RepoFgpMetadata.description_for(fgp)
  end

  # FGP contains the metadata for an individual fine grained permission
  def self.for(fgp)
    new(fgp.to_sym)
  end

  # Public: get all the categories and FGPs for a role
  #
  # - role: the Role object
  #
  # Returns a Hash of categories titles to FGP descriptions
  def self.for_role(role)
    for_permissions(role.permissions)
  end

  # Public: get all the categories and FGPs for multiple roles
  #
  # - roles: an Array of Role objects
  #
  # Returns a Hash of categories titles to FGP descriptions
  def self.for_roles(roles)
    for_permissions(roles.flat_map(&:permissions))
  end

  # Public: get FGPs for a role, grouped by category title
  #
  # - role: the Role object
  #
  # Returns a Hash of category titles to arrays of FineGrainedPermissionIm objects:
  #   {
  #     "Issue" => [<FGP>, <FGP>],
  #     "Pull Request" => [<FGP>, <FGP>]
  #   }
  #   Sorted by CATEGORY_ORDER
  def self.fgps_for_role(role)
    fgps = fgps_for_permissions(role.permissions)

    CATEGORY_ORDER.each_with_object({}) do |category, result|
      category_fgps = fgps.select { |fgp| fgp.category == category }
      result[title_for(category)] = category_fgps unless category_fgps.empty?
    end
  end

  private_class_method def self.fgps_for_permissions(permissions)
    actions = permissions.map(&:action)
    Permissions::FineGrainedPermissionIm.where(actions: actions, target_type: "Repository")
  end

  private_class_method def self.for_permissions(permissions)
    fgps_by_category = fgps_for_permissions(permissions).group_by(&:category)

    CATEGORY_ORDER.each_with_object({}) do |category, result|
      next unless (fgps = fgps_by_category[category])

      result[title_for(category)] = fgps.map(&:description)
    end
  end

  def self.categories
    CATEGORY_ORDER
  end

  def self.category_for(fgp)
    return :unknown unless (fgp_im = Permissions::FineGrainedPermissionIm.repo_fgps_for_custom_roles.find { |f| f.action == fgp.to_s })

    fgp_im.category || :unknown
  end

  def self.description_for(fgp)
    return "unknown" unless (fgp_im = Permissions::FineGrainedPermissionIm.repo_fgps_for_custom_roles.find { |f| f.action == fgp.to_s })

    fgp_im.description || "unknown"
  end

  # Public: the human readable title for every FGP category
  def self.title_for(category)
    case category
    when :issues
      "Issue"
    when :prs
      "Pull Request"
    when :issues_prs
      "Issue and Pull Request"
    when :repository
      "Repository"
    when :security
      "Security"
    when :discussions
      "Discussions"
    when :merge_queue
      "Merge Queue"
    when :ci_cd
      "CI/CD"
    when :copilot
      "Copilot"
    end
  end

  # Public: the octicon for every FGP category
  def self.icon_for(category)
    case category
    when :issues
      "issue-opened"
    when :prs
      "git-pull-request"
    when :issues_prs
      "file-diff"
    when :repository
      "repo"
    when :security
      "shield"
    when :discussions
      "comment-discussion"
    when :merge_queue
      "git-merge-queue"
    when :ci_cd
      "workflow"
    when :copilot
      "copilot"
    end
  end

  # Public: the octicon for every FGP category by title
  def self.icon_for_title(title)
    case title
    when "Issue"
      "issue-opened"
    when "Pull Request"
      "git-pull-request"
    when "Issue and Pull Request"
      "file-diff"
    when "Repository"
      "repo"
    when "Security"
      "shield"
    when "Discussions"
      "comment-discussion"
    when "Merge Queue"
      "git-merge-queue"
    when "CI/CD"
      "workflow"
    when "Copilot"
      "copilot"
    end
  end

  CATEGORY_ORDER = %i(issues_prs issues prs merge_queue repository security discussions ci_cd copilot).freeze
end
