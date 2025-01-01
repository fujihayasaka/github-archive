# typed: true
# frozen_string_literal: true

require "github/null_objects"
require "legacy_importable"

require_relative "content_authorization_error"
require_relative "email_verification_required"

# Public: Responsible for handling "can a user do this kind of thing?" logic.
# This is not designed to determine whether a user has the Ability to do a
# specific thing in a specific context. It answers questions like:
#
# - Can an actor do the given kind of thing generally? (e.g. whether a user can
#   create a repository or leave commit comments)
# - Can the operation be done in the given context? (e.g. whether an issue can
#   accept comments at all, or, whether an issue can be opened on a repo)
class ContentAuthorizer
  VALID_OPERATIONS = [:new, :create, :edit, :update, :delete, :destroy]

  include LegacyImportable

  attr_reader :actor, :operation

  def initialize(actor, operation, data)
    unless self.class.valid_operations.include?(operation = operation.to_sym)
      raise ArgumentError, "Invalid operation #{operation}. Must be one of: #{self.class.valid_operations.join(', ')}."
    end

    @actor = case actor
    when nil, :anonymous
      GitHub::NullUser.new
    else
      actor
    end
    @operation = operation
  end

  # Public: Instantiate a ContentAuthorizer object.
  # Deprecated: Subclass ContentAuthorizer and instantiate directly instead. See Issues::ContentAuthorizer for an example.
  #
  # actor        - The user attempting to create or mutate content
  # content_type - A symbol representing the type of content the actor wants
  #                to create or mutate
  # operation    - The action the actor wants to take (one of valid_operations).
  #                Defaulted to :create.
  # context      - A Hash containing information needed to make a decision
  #                about whether the actor is authorized to make a change.
  #
  # Examples
  #
  #   ContentAuthorizer.authorize(current_user, :issue_comment, :issue => issue)
  #   # => <ContentAuthorizer::IssueCommentAuthorizer>
  #
  # Returns an instance of the appropriate ContentAuthorizer subclass.
  def self.authorize(actor, content_type, operation = :create, context = {})
    klass = content_type_for(content_type)

    unless klass
      raise ArgumentError, "Unknown content_type: #{content_type}"
    end

    klass.new(actor, operation, context)
  end

  def self.content_type_for(content_type)
    # Ideally we would enforce consistency here
    content_type = content_type.to_s.camelize

    # DO NOT ADD MORE CASES TO THIS LIST! Instead, create a new subclass of
    # ContentAuthorizer and instantiate it directly at the relevant call sites.
    # See Issues::ContentAuthorizer usage for an example.
    case content_type
    when "Blob"                   then ContentAuthorizer::BlobAuthorizer
    when "CommitComment"          then ContentAuthorizer::CommitCommentAuthorizer
    when "Deployment"             then ContentAuthorizer::DeploymentAuthorizer
    when "DeploymentStatus"       then ContentAuthorizer::DeploymentStatusAuthorizer
    when "Discussion"             then ContentAuthorizer::DiscussionAuthorizer
    when "DiscussionComment"      then ContentAuthorizer::DiscussionCommentAuthorizer
    when "DiscussionPost"         then ContentAuthorizer::DiscussionPostAuthorizer
    when "Hook"                   then ContentAuthorizer::HookAuthorizer
    when "Issue"                  then Issues::ContentAuthorizer
    when "IssueComment"           then ContentAuthorizer::IssueCommentAuthorizer
    when "Label"                  then ContentAuthorizer::LabelAuthorizer
    when "MergeQueue"             then ContentAuthorizer::MergeQueueAuthorizer
    when "OrganizationInvitation" then ContentAuthorizer::OrganizationInvitationAuthorizer
    when "Project"                then ContentAuthorizer::ProjectAuthorizer
    when "PullRequest"            then ContentAuthorizer::PullRequestAuthorizer
    when "PullRequestComment"     then ContentAuthorizer::PullRequestCommentAuthorizer
    when "Repo"                   then ContentAuthorizer::RepoAuthorizer
    when "ReportContent"          then ContentAuthorizer::ReportContentAuthorizer
    when "Star"                   then ContentAuthorizer::StarAuthorizer
    when "Status"                 then ContentAuthorizer::StatusAuthorizer
    when "Wiki"                   then ContentAuthorizer::WikiAuthorizer
    else nil
    end
  end

  # Public: All of the valid operations an actor can take. Usually,
  # this will just be VALID_OPERATIONS, but can be overridden in
  # subclasses when necessary.
  #
  # Returns an array of symbols representing the valid operations
  # that can be performed.
  def self.valid_operations
    VALID_OPERATIONS
  end

  # Public: Can the ContentAuthorizer be used for the given type
  # of content?
  #
  # content_type - string or symbol
  def self.can_authorize?(content_type)
    content_type_for(content_type)
  end

  # Public: Is the actor authorized to create or mutate the given kind of
  # content? Aliased to `passed?` for readability.
  #
  # Examples
  #
  #   authorization.authorized?
  #   # => false
  def authorized?
    errors(fail_fast: true).none?
  end
  alias_method :passed?, :authorized?

  # Public: Inverse of `authorized?`. Indicates that the actor is not authorized
  # to create or mutate the given kind of content.
  def unauthorized?
    !authorized?
  end
  alias_method :failed?, :unauthorized?

  def errors(*attrs)
    raise NotImplementedError
  end

  # Public: Check for the presence of email verification errors. Used to
  # handle messaging for this kind of error in a special way.
  def has_email_verification_error?
    errors.any? do |error|
      error.kind_of?(ContentAuthorizationError::EmailVerificationRequired)
    end
  end

  # Public: Full list of human-readable errors preventing this actor from
  # creating or mutating the given kind of content.
  def error_messages
    return "" if errors.blank?
    messages = errors.map(&:message).map do |msg|
      msg.sub(/\A[A-Z]/) { |char| char.downcase } # ensure first letter is lowercase
         .sub(/\.\z/, "")                         # strip punctuation
    end.to_sentence

    messages.upcase_first
  end

  # Public: The first error encountered. The API returns only one error
  # at a time, so there's no reason to grab them all.
  def first_error
    @first_error ||= errors(fail_fast: true).first
  end
  alias_method :api_error, :first_error

  # Public: The api_error_payload of the first ContentAuthorizationError
  def api_error_payload
    api_error.api_error_payload if unauthorized?
  end

  # Public: The HTTP status code appropriate for the error that will be
  # returned via the API, if any.
  def http_error_code
    api_error.http_error_code if unauthorized?
  end

  def self.operations_requiring_verified_email
    valid_operations - [:delete, :destroy]
  end

  private

  # Private: When mandatory email verification is enabled, is this one
  # of the content operations where verification is required?
  def verified_email_required_to?(operation)
    self.class.operations_requiring_verified_email.include?(operation)
  end

  # Internal: Is this github process running some kind of automated data
  # transformation, like a backfill or an import?
  #
  # Returns a boolean.
  def in_automated_data_transformation?
    importing? || GitHub.context[:transition].present?
  end
end
