# typed: false
# frozen_string_literal: true

module Repository::ForkerMethods
  include Repos::GitHubEnterpriseHelper
  include GitHub::UTF8

  def build_new_repository
    # what attributes are we copying?
    default_attrs = parent_repository.attributes.slice(*Repository::FIELDS_COPIED_ON_FORK)

    # what attributes are unique to the fork
    new_attributes = default_attrs.deep_symbolize_keys.merge({
      parent: parent_repository,
      has_issues: false,
      name: data[:name] || Platform::Loaders::NewForkName.load(owner, parent_repository.name).sync,
      created_by_user_id: forker.id,
      wiki_access_to_pushers: true,
      description: description || default_attrs["description"],
    })

    # ensure repository description is utf-8 encoded
    # utf8() will replace non-utf8 characters with ?s
    new_attributes[:description] = utf8(new_attributes[:description]) if new_attributes[:description]
    # strip out control characters from description, which are invalid
    # See https://github.com/github/github/issues/42763
    new_attributes[:description] = new_attributes[:description].gsub(/[[:cntrl:]]/, "") if new_attributes[:description]
    # truncate the description to the current character limit
    new_attributes[:description] = new_attributes[:description][0...::Repository::DESCRIPTION_CHAR_LIMIT] if new_attributes[:description]

    new_repo = owner.repositories.build(new_attributes)
    new_repo.one_branch_fork = data[:one_branch]

    new_repo
  end

  def set_fork_error(reason:, fork_repository_errors: nil)
    errors.add(:fork_repository, reason, message: Repository::ForkerMethods.message_from_reason(reason, fork_repository_errors))
  end

  def should_set_new_repo_to_internal?
    # If the parent repo is internal and the fork is owned by an org, the new repo should also be internal.
    # Personal forks should be private as internal repositories are restricted to enterprise orgs.
    parent_repository.internal? && repository.owner.organization?
  end

  # Should the forker be an admin of the new fork?
  #
  # When a user creates a new repo in an org, they receive admin access to the repository. For forks, we should do the
  # same if the fork is created in an org.
  #
  # Return a boolean indicating whether the forker should be an admin of the new fork.
  def should_set_forker_as_admin?
    repository.owner.organization? && !repository.adminable_by?(forker)
  end

  def allowed_request_for_intra_org_fork?
    owner.organization? && owner.same_org_as_repo?(parent_repository)
  end

  def allowed_multi_fork_request_for_org?
    owner.organization?
  end

  def violating_enterprise_policy?
    # Forker is EMU or GH[ES|AE] user trying to fork the repository into their account which is not allowed.
    (emu_gated_with_feature_flag? || is_enterprise_to_restrict_for_personal_namespace?) &&
      owner_is_personal_account? &&
      creating_repo_in_personal_namespace_enterprise_setting_enabled?
  end

  def emu_gated_with_feature_flag?
    forker.is_enterprise_managed?
  end

  def is_enterprise_to_restrict_for_personal_namespace?
    GitHub.single_business_environment?
  end

  def creating_repo_in_personal_namespace_enterprise_setting_enabled?
    restrict_create_repositories_in_personal_namespace?(forker)
  end

  def owner_is_personal_account?
    forker == owner
  end

  def self.message_from_reason(reason, errors)
    case reason
    when :forking
      "Being forked, check now"
    when :exists
      "Forked, check now"
    when :invalid
      if errors.is_a?(Hash)
        build_message_from_hash(errors)
      else
        errors.full_messages.to_sentence
      end
    when :account
      "You can't fork this repository at this time."
    when :permission
      "Don’t have permission to fork this repository"
    when :policy
      "You cannot fork this repository to the selected destination due to a policy."
    when :org_private
      "You cannot fork a private repository into an organization outside the repository's enterprise."
    when :plan
      "You can't fork a private repository into an organization on a free plan. Sorry about that!"
    when :private_fork
      "Cannot fork a private fork."
    when :fork_of_internal
      "Forks of internal repositories cannot be forked again."
    when :duplicate_of_existing_fork
      "Repository is already being forked."
    when :spammy_user
      "You cannot fork this repository at this time"
    when :new_user
      "Please try again later."
    when :deleted_owner
      "The owner of this fork is deleted."
    end
  end

  def self.build_message_from_hash(errors)
    error_messages = errors.map do |attribute, messages|
      next messages if attribute == :base

      messages.map do |message|
        "#{attribute.to_s.humanize} #{message}"
      end
    end

    error_messages.flatten.to_sentence
  end

end
