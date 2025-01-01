# typed: true
# frozen_string_literal: true

class Businesses::Settings::AdminCenterOptionsView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  include ApplicationHelper

  def force_detail_text
    case GitHub.force_push_rejection_original_value
    when "false"
      "Allowed"
    when "all"
      "Blocked"
    when "default"
      "Blocked on the default branch"
    when nil
      "Allowed"
    end
  end

  def force_rejection_choices
    choices = T.let([
      ["Allow", "false"],
      ["Block", "all"],
      ["Block to the default branch", "default"],
    ], T::Array[T::Array[T.nilable(String)]])

    if GitHub.force_push_rejection_original_value.nil?
      # There's no manual setting yet, so we're using git's default
      choices.unshift(["git's default (Allow)", nil])
    else
      # Clear out manual setting and go back to git's default
      choices << ["Clear and use git’s default (Allow)", "_clear"]
    end

    choices
  end

  def ssh_choices
    choices = T.let([
      %w[Enabled true],
      %w[Disabled false],
    ], T::Array[T::Array[T.nilable(String)]])

    if GitHub.ssh_enabled_original_value.nil?
      # There's no manual setting yet, so we're using git's default
      choices.unshift(["git's default (Enabled)", nil])
    else
      # There's no setting that will cascade, so we'll use git's default
      choices << ["Clear and use git's default (Enabled)", "_clear"]
    end

    choices
  end

  def suggested_protocol_choices
    [
      ["Default (last used)", "sticky"],
      ["HTTPS", "http"],
      ["SSH (if available)", "ssh"],
    ]
  end

  def suggested_protocol_text
    index = suggested_protocol_choices.map(&:last).find_index(GitHub.suggested_protocol) || 0

    suggested_protocol_choices[index].first
  end

  def org_creation_choices
    choices = [
      %w[Enabled true],
      %w[Disabled false],
    ]

    choices
  end

  def allow_comment_authors_profile_name_choices
    choices = [
      %w[Enabled true],
      %w[Disabled false],
    ]

    choices
  end

  def org_membership_visibility_choices
    [
      %w[Private private],
      %w[Public public],
    ]
  end

  def non_site_admins_can_create_repositories_choices
    choices = [
      %w[Enabled true],
      %w[Disabled false],
    ]

    choices
  end

  def repo_default_choices
    [
      %w[Public public],
      %w[Private private],
      %w[Internal internal],
    ].tap { |choices| choices.shift unless GitHub.public_repositories_available? }
  end

  def repo_default_text
    index = repo_default_choices.map(&:last).find_index(GitHub.default_repo_visibility) || 0
    repo_default_choices[index].first
  end

  def git_lfs_choices
    choices = [
      %w[Enabled true],
      %w[Disabled false],
    ]

    choices
  end

  def showcase_choices
    choices = [
      %w[Disabled false],
      %w[Enabled true],
    ]

    choices
  end

  def cross_repo_conflict_editor_choices
    choices = [
      %w[Enabled true],
      %w[Disabled false],
    ]

    choices
  end

  def max_object_size_choices
    choices = [
      ["1MB", 1],
      ["5MB", 5],
      ["10MB", 10],
      ["25MB", 25],
      ["50MB", 50],
      ["Default (#{GitHub.default_max_object_size}MB)", GitHub.default_max_object_size],
      ["150MB", 150],
      ["200MB", 200],
      ["250MB", 250],
      ["300MB", 300],
      ["350MB", 350],
      ["500MB", 500],
      ["750MB", 750],
      ["1GB", 1000],
    ]

    if GitHub.unlimited_max_object_size_enabled?
      choices << ["Unlimited", 0]
    end

    choices
  end

  # Maximum object size controls
  def max_object_size_detail_text
    case GitHub.max_object_size
    when 0
      "Unlimited"
    when 1000
      "1GB"
    when GitHub.default_max_object_size
      "Default (#{GitHub.default_max_object_size}MB)"
    else
      "#{GitHub.max_object_size}MB"
    end
  end

  def reactivate_suspended_users_note
    return unless GitHub.auth.external?
    "Unsuspend users when they successfully authenticate via #{GitHub.auth_mode.upcase}."
  end

  def reactivate_suspended_users_on_sync_note
    return unless GitHub.auth.external?
    return unless GitHub.ldap_sync_enabled?
    "Unsuspend users when an LDAP Sync occurs."
  end

  def reactivate_suspended_users_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def ldap_debugging_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def saml_debugging_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end

  def dormancy_threshold_choices
    Configurable::EnterpriseDormancyThreshold::VALID_DORMANCY_THRESHOLD_DAYS_VALUES.map do |days|
      label = helpers.pluralize(days, "day")
      label = "#{label} (default)" if days == Configurable::EnterpriseDormancyThreshold::DEFAULT_DORMANCY_THRESHOLD_DAYS
      [label, days.to_s]
    end
  end

  def dormancy_threshold_button_text
    dormancy_threshold_choices.each do |label, value|
      return label if value == GitHub.enterprise_dormancy_threshold_days.to_s
    end
  end

  def anonymous_access_choices
    [
      %w[Enabled true],
      %w[Disabled false],
    ]
  end
end
