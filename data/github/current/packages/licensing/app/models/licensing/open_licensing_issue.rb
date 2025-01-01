# typed: true
# frozen_string_literal: true

class Licensing::OpenLicensingIssue

  LICENSING_REPO_NWO = "github/licensing"
  LICENSING_REPO_ID = 691766258
  ISSUE_LABELS = ["slack🧵"]

  # Public: Initialize a new command object
  #
  # title - The title that will be used to create the issue
  # description - The description that will be used to create the issue
  sig { params(title: T.nilable(String), description: T.nilable(String)).returns(T.nilable(Issues::IIssue)) }
  def self.create(title, description)
    new(title, description).create
  end

  # Public: Initialize a new command object
  #
  # title - The title that will be used to create the issue
  # description - The description that will be used to create the issue
  sig { params(title: T.nilable(String), description: T.nilable(String)).void }
  def initialize(title, description)
    @title = title
    @description = description
  end

  # Public: Determines whether we will be able to create an issue by validating title and
  # description args are present and confirms we are able to find the licensing repo
  #
  # Returns true or false
  sig { returns(T::Boolean) }
  def valid?
    if [@title, @description].any?(&:blank?)
      Failbot.report(ArgumentError.new "title and description required")
      return false
    end

    return false unless repo
    return false unless licensing_repo?

    true
  end

  # Public: Creates a new licensing issue or returns nil if we can't
  #
  # Returns Issue or nil
  sig { returns(T.nilable(Issues::IIssue)) }
  def create
    return unless valid?

    create_issue_attributes = ::Issues::CreateIssueAttributes.new(title: title, repository: T.must(repo))
    create_issue_attributes.body = description
    create_issue_attributes.labels = labels.to_a

    result = ::Issues.domain.create(
      create_issue_attributes,
      User.staff_user,
      skip_permission_checks: true,
    )
    result.ok
  end

  private

  attr_reader :title, :description

  # Internal: This method will check if the licensing repo exists
  #
  # Returns true or false
  sig { returns(T::Boolean) }
  def licensing_repo?
    "#{T.must(repo).owner_display_login}/#{T.must(repo).name}" == LICENSING_REPO_NWO
  end

  sig { returns(ActiveRecord::Relation) }
  def labels
    T.must(repo).labels.where(name: ISSUE_LABELS)
  end

  sig { returns(T.nilable(Repository)) }
  def repo
    @repo ||= Repositories::Public.find_active(LICENSING_REPO_ID)
  end

end
