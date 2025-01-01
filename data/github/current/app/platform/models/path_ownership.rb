# typed: true
# frozen_string_literal: true

class Platform::Models::PathOwnership
  include ActionView::Helpers::TagHelper

  # codeowners - An instance of Repository::Codeowners associated to the path
  # diff - An instance of Platform::Models::Diff related to this object
  # path - The path for the diff entry
  def initialize(path:, codeowners:, diff:)
    @codeowners = codeowners
    @diff = diff
    @path = path
  end

  attr_reader :diff, :path

  # Path Owners list derived from the CODEOWNERS file for the file path
  #
  # Returns Array of ::PathOwner objects
  def path_owners
    @codeowners.repository.async_organization.then do
      @codeowners.owners_for_path(path).map do |owner_name|
        Platform::Models::PathOwner.new(name: owner_name)
      end
    end
  end

  # Is this object owned by the given viewer?
  #
  # viewer - User
  #
  # Returns Boolean
  def owned_by_viewer?(viewer)
    @codeowners.owned_by?(owner: viewer, path: path)
  end

  # The line number where ownership rule for this object is defined
  #
  # Returns Integer or nil
  def rule_line_number
    @codeowners.rule_for_path(path)&.line
  end

  # URL where ownership rule for this object is defined
  #
  # Returns URI encoded String if codeowners rule is present
  # Returns nil if codeowners rule is not present
  def rule_url
    return if rule_line_number.nil?

    repo = diff.repo.name_with_display_owner
    oid = @codeowners.ref
    path = @codeowners.path

    Addressable::URI.encode(
      "#{GitHub.url}/#{repo}/blob/#{oid}/#{path}#L#{rule_line_number}"
    )
  end
end
