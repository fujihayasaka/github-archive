# typed: true
# frozen_string_literal: true

# Public: Validates a query param String adheres to the expected format
#         for identifying a Repository-, Organization-, or User-owned Project.
#
# Valid params look like:
#
#    org/123
#    user/repo/123
#    org/repo/123
#
class ProjectQueryParam
  attr_reader :owner_display_login
  attr_reader :repository_name
  attr_reader :number
  attr_reader :param

  NUMBER = /(?:\d+)\b/.freeze

  # Example: "github/github", "github"
  NAME_OR_NWO = /(?:\w+(?:-\w+)*(?:\/[.\w-]+)?)/.freeze
  # Example: "github/github/1", "github/1"
  SHORTHAND = %r{(?<shorthand>(#{NAME_OR_NWO})\/(#{NUMBER}))}.freeze

  # Public: Initialize a new ProjectQueryParam instance.
  #
  # param - The String value that may identify a Project record.
  # repository - (Optional) A Repository record to match the param against.
  # owner -(Optional) A project owner to match the param against.
  #
  # The param String should be in one of the following forms:
  #
  #    org/123
  #    user/repo/123
  #    org/repo/123
  #
  # If it isn't then, #valid? will return false and other properties
  # will be nil.
  #
  # If a Repository is given, then the "repo" portion of the above
  # examples must be present and must match the Repository's name.
  #
  # If an Organization-type owner is given, then the "org" portion must match
  # the Organization's login.
  #
  # Matching is case-insensitive.
  #
  # If both a Repository and an Organization-type owner are given, an
  # ArgumentError will be raised if the Repository doesn't belong to the
  # Organization.
  #
  # Returns a ProjectQueryParam.
  def initialize(param:, repository: nil, owner: nil)
    validate_ownership(owner: owner, repository: repository)

    @param = param
    owner = owner || repository&.owner
    matcher = matcher_regexp(repository: repository, owner: owner)

    if match = matcher.match(@param)
      @owner_display_login = match[:owner_display_login]
      @repository_name = match[:repository_name]
      @number = match[:number].to_i
    end
  end

  # Public: Does the param string represent a project identifier?
  #
  # Validity is defined as having a recognized owner_display_login and number.
  #
  # Note that validity makes no claim about the presence of a corresponding
  # database record.
  #
  # Returns a boolean.
  def valid?
    !!(owner_display_login && number)
  end

  # Public: Does the project this param points to belong to a Repository?
  #
  # True for params of the form `owner/repo/123`.
  #
  # Returns a boolean.
  def repository_project?
    repository_name.present? && valid?
  end

  private

  # Private: Create a regular expression that matches the basic format
  #          and optionally requires the owner login and repository name
  #          to match those given.
  #
  # The Regexp will return match entries for :owner_display_login, :repository_name,
  # and :number.
  #
  # Returns a Regexp.
  def matcher_regexp(repository: nil, owner: nil)
    owner_display_login_regexp = owner ? /#{Regexp.escape(owner.display_login)}/i : /[a-z0-9][a-z0-9\-\_]*/i
    repository_name_regexp = repository ? /#{Regexp.escape(repository.name)}/i : /(?:\w|\.|\-)+/i

    /\A
    (?<owner_display_login>#{owner_display_login_regexp})\/
    (?:(?<repository_name>#{repository_name_regexp})\/)?
    (?<number>\d+)
    \z/ix
  end

  def validate_ownership(owner:, repository:)
    if owner && repository && repository.owner != owner
      if repository.public?
        error_message = "#{repository.name_with_display_owner} must belong to #{owner.display_login}"
      else
        error_message = "#{repository.id} must belong to #{owner.display_login}"
      end
      raise ArgumentError.new(error_message)
    end
  end
end
