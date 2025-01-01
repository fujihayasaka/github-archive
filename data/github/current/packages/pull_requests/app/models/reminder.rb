# typed: true
# frozen_string_literal: true

class Reminder < ApplicationRecord::Collab
  include ReminderScheduling
  include GitHub::IFlipperActor
  include GitHub::VexiActor

  MAX_ASSOCIATED_TEAMS = 100

  has_many :repository_links, class_name: "ReminderRepositoryLink", dependent: :destroy
  has_many :team_memberships, class_name: "ReminderTeamMembership", dependent: :destroy
  has_many :teams, -> (reminder) { where(organization: reminder.remindable) }, through: :team_memberships, disable_joins: true

  # rubocop:todo Rails/InverseOf
  belongs_to :slack_workspace, -> (reminder) { for_remindable(reminder.remindable) },
    class_name: "ReminderClientWorkspace",
    foreign_key: "reminder_slack_workspace_id"
  # rubocop:enable Rails/InverseOf
  belongs_to :remindable, polymorphic: true

  belongs_to :user

  before_validation :format_slack_channel
  before_validation :default_age_staleness_values
  before_validation :reset_include_reviewed_prs_settings

  before_save :create_repository_links # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  validates :slack_workspace, presence: true
  validates :slack_channel, presence: true, format: { with: /\A[a-z0-9\-_]+\z/, message: "must be lowercase without spaces, periods, or special characters and 80 characters or less." }, unless: [:teams_workspace?, :add_by_channel_id_or_name?]
  validates :slack_channel, presence: true, format: { with: /\A[a-z0-9\-_]+\z|\A[A-Z0-9]+\z/, message: "must be either a channel name (lowercase without spaces, periods, or special characters and 80 characters or less) or a channel ID (similar to C1234567890)" }, if: proc { T.bind(self, Reminder); add_by_channel_id_or_name? && !teams_workspace? }
  validates :remindable, presence: true

  before_destroy :generate_webhook_payload # rubocop:todo GitHub/AvoidActiveRecordCallbacks
  after_commit :instrument_destruction, on: :destroy # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  scope :for_remindable, -> (remindable) { where(remindable: remindable) }

  scope :tied_to_single_team, -> {
    joins(:team_memberships)
      .group("reminders.id")
      .having("count(reminder_team_memberships.reminder_id) = 1")
  }

  scope :order_by_workspace, -> {
    joins("JOIN reminder_slack_workspaces ON reminder_slack_workspace_id = reminder_slack_workspaces.id")
    .order("reminder_slack_workspaces.name ASC, reminders.id ASC")
  }

  scope :with_repo_nwo, ->(nwo) {
    where(id: with_linked_repo(nwo))
    .or(
      where(id: for_all_repos)
    )
  }

  scope :with_linked_repo, ->(nwo) {
    org, repo_name = nwo.split("/")
    repo_id = Repository.find_by(name: repo_name, owner_login: org)&.id
    if repo_id
      joins(:repository_links).where(reminder_repository_links: { repository_id: repo_id })
    else
      none
    end
  }

  scope :for_all_repos, -> {
    left_joins(:repository_links)
    .where(reminder_repository_links: { id: nil })
  }

  validate :teams_belong_to_same_organization
  validate :less_than_max_teams

  attr_accessor :dont_validate_repos_accessible
  validate :some_repos_accessible
  validate :repositories_are_public
  validate :check_slack_workspace
  validates :ignored_terms, length: { maximum: 1024 }
  validates :ignored_labels, length: { maximum: 1024 }
  validates :required_labels, length: { maximum: 1024 }
  validates :min_age, numericality:  { only_integer: true, greater_than_or_equal_to: 0 }
  validates :min_staleness, numericality:  { only_integer: true, greater_than_or_equal_to: 0 }

  extend GitHub::Encoding
  force_utf8_encoding :ignored_terms, :ignored_labels, :required_labels

  def teams_workspace?
    slack_workspace&.type == "ReminderTeamsWorkspace"
  end

  # allow only the repositories the user has access to
  # if filters is empty get the repoid's that the user has access to unless the user is the admin
  def user_accessible_repository_ids(filters)
    if filters.empty?
      filters = []
      if remindable.adminable_by?(user)
        filters
      else
        filters << remindable.repositories_associated_with(user).pluck(:id)
      end
    else
      filters.each_with_object([]) do |repo_ids, user_accessible_repository_ids|
        associated_repo_ids = user&.associated_repository_ids(repository_ids: repo_ids) || []
        user_accessible_repository_ids.push(associated_repo_ids)
      end
    end
  end

  def create_repository_links
    filtered_repo_ids = tracked_repository_ids
    filtered_repo_ids = filtered_repo_ids & team_repository_ids if teams.present?
    filtered_repo_ids = remindable.repositories.where(id: filtered_repo_ids).pluck(:id)

    current_repo_links = self.repository_links.index_by(&:repository_id)
    self.repository_links = filtered_repo_ids.map do |repo_id|
      current_repo_links[repo_id] || repository_links.build(repository_id: repo_id)
    end

    @tracked_repository_ids = nil
    repository_links
  end

  # Preserves functionality to de-dupe accidental team duplication that would cause an error.
  # This could be caused by user input as [1, 1] is valid input from the user side of things.
  def teams=(teams)
    super([teams].flatten.uniq)
  end

  def check_slack_workspace
    return if slack_workspace.nil?

    if slack_workspace&.remindable != remindable
      self.slack_workspace = nil
      self.errors.add(:slack_workspace, "can't be blank")
    end
  end

  def reset_include_reviewed_prs_settings
    unless include_reviewed_prs
      self.needed_reviews = 0
    end

    if include_reviewed_prs && !require_review_request
      self.include_reviewed_prs = false
    end
  end

  def description(include_team: true)
    # These modifiers go after the word "pull requests"
    description = if ignore_draft_prs
      "Any non-draft pull request"
    else
      "Any pull request"
    end

    if ignore_after_approval_count > 0
      description += " with less than #{ignore_after_approval_count} #{"approval".pluralize(ignore_after_approval_count)}"
    end

    # If we are tracking the repos, then we don't need to specify the teams
    # Because the repo filters will be more specific
    repos = tracked_repositories # Use tracked_repos and not ids so we filter out private repos if necessary
    if repos.size > 0 && repos.size < 3
      description += " on #{repos.map(&:name_with_display_owner).sort.to_sentence}"
    elsif repos.size >= 3
      description += " on #{repos.size} #{"repository".pluralize(repos.size)}"

    # Otherwise, if we track all repos, then we want to specify the teams on which we filter
    elsif require_review_request && include_team && teams.size > 0 && teams.size < 3
      description += " requesting review from #{teams.map(&:name).sort.to_sentence}"
    elsif require_review_request && include_team && teams.size >= 3
      description += " requesting review from the #{teams.size} selected teams"

    # However, if we have all teams then we can just specify the repos in the org
    else
      description += " on all"
      description += " public" unless supports_private_repos?
      description += " repositories in the #{remindable.display_login} organization"
    end

    description.strip
  end

  def some_repos_accessible
    return if @dont_validate_repos_accessible
    # If accessible repository ids is `nil`, that means we target everything on the organization
    # Otherwise, we are filtering and we need to check to make sure everything works as expected
    return if accessible_repository_ids.nil? || !accessible_repository_ids.empty?

    if teams.present?
      self.errors.add(:base, "No repositories visible with the selected settings and teams")
    else
      self.errors.add(:base, "No repositories visible with the selected settings")
    end
  end

  # Validate that all repos are public unless we support private repos.
  def repositories_are_public
    return if supports_private_repos?

    # Don't use tracked_repos because we want to validate based only on the user's selected IDs
    repos = Repository.where(id: tracked_repository_ids)
    return if repos.all?(&:public?)

    self.errors.add(:base, "The plan for the #{remindable.display_login} organization does not allow you to add reminders for private repositories")
  end

  def teams_belong_to_same_organization
    team_from_another_organization = Team
      .where(id: team_ids)
      .where.not(organization_id: remindable_id)
      .exists?

    if team_from_another_organization
      self.teams = []
      self.errors.add(:teams, "could not all be found")
    end
  end

  def less_than_max_teams
    if team_ids.count > MAX_ASSOCIATED_TEAMS
      self.errors.add(:base, "Cannot have more than #{MAX_ASSOCIATED_TEAMS} teams associated to a single reminder")
    end
  end

  def format_slack_channel
    self.slack_channel = self.slack_channel[1..-1] || "" if self.slack_channel.start_with?("#")
    self.slack_channel = self.slack_channel.strip # Remove whitespace
  end

  def default_age_staleness_values
    self.min_age = 0 if self.min_age.nil?
    self.min_staleness = 0 if self.min_staleness.nil?
  end

  def reset_memoized_attributes
    @teams = nil
    @tracked_repository_ids = nil
    @supports_private_repos = nil
  end

  def include_approved?
    ignore_after_approval_count.to_i < 1
  end

  def include_drafts?
    !ignore_draft_prs
  end

  def too_many_approvals?(number_of_approvals)
    return false if include_approved?

    number_of_approvals >= ignore_after_approval_count
  end

  def targetting_all_repos?
    # To follow the same implicit pattern as an Integration, a reminder is targetting all repos if the tracked_repos is empty
    tracked_repository_ids.empty?
  end

  # Can't use has_many through because Repository and
  # ReminderRepositoryLink are in different databases
  def tracked_repositories
    repo_ids = tracked_repository_ids
    repo_ids = repo_ids & team_repository_ids if teams.present?

    repos = remindable.repositories.where(id: repo_ids)
    repos = repos.public_scope unless supports_private_repos?
    repos
  end

  def tracked_repository_ids=(repo_ids)
    @tracked_repository_ids = repo_ids.map(&:to_i)
  end

  def tracked_repository_ids
    @tracked_repository_ids ||= repository_links.map(&:repository_id)
  end

  def filtered_pull_requests
    if user&.feature_enabled?(:reminder_pull_request_filter_increased_batch_size)
      ReminderPullRequestFilter.batch_size = 500
      ReminderPullRequestFilter.run(self)
    else
      ReminderPullRequestFilter.run(self)
    end
  ensure
    ReminderPullRequestFilter.reset_batch_size
  end

  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def integration_installation
    @integration_installation ||= begin
      integration = if slack_workspace&.type == "ReminderTeamsWorkspace"
        Apps::Privileged.integration(:msteams)
      else
        Apps::Privileged.integration(:slack)
      end

      if remindable && integration
        integration.installations_on(remindable).first
      end
    end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  def team_repository_ids
    teams.flat_map { |t| t.direct_or_inherited_repo_ids(affiliation: :all) }.uniq
  end

  def supports_private_repos?
    return false if remindable.nil?
    @supports_private_repos ||= remindable.plan_supports?(:reminders, visibility: "private", fallback_to_free: false)
  end

  def accessible_repository_ids
    # If we are not installed on this org, then we have access to nothing
    return [] if integration_installation.nil?

    filters = []

    unless supports_private_repos?
      filters << remindable.repositories.public_scope.pluck(:id)
    end

    unless integration_installation.installed_on_all_repositories?
      filters << integration_installation.repository_ids
    end

    if teams.present?
      filters << team_repository_ids
    end

    unless targetting_all_repos?
      filters << tracked_repository_ids
    end

    if user && GitHub.flipper[:scheduled_reminders_teams_parity].enabled?(user) && teams_workspace?
      filters = user_accessible_repository_ids(filters)
    end
    # If we have nothing to filter, then we are installed on all repos,
    # reminders is filtering on all repos, and there are no teams selected.
    # Therefore there is nothing to filter. Return nil in this case.
    if filters.empty?
      nil
    else
      filters = filters.inject(&:&) # Intersect all the filter arrays together
      filters
    end
  end

  def permitted_to_repository_id?(repository_id)
    # Returns nil if all repositories are accessible
    repository_ids = accessible_repository_ids
    repository_ids.nil? || repository_ids.include?(repository_id)
  end

  def ignored_terms_values
    ignored_terms.to_s.split(",").map(&:strip)
  end

  def ignored_labels_values
    ignored_labels.to_s.split(",").map(&:strip)
  end

  def required_labels_values
    required_labels.to_s.split(",").map(&:strip)
  end

  def has_valid_associations?
    remindable.present?
  end

  def event_subscriptions
    []
  end

  def api_hash
    if remindable.nil?
      GitHub.dogstats.increment("pull_request_reminder.missing_remindable")
      return {}
    end
    team_list = teams.map do |team|
      {
        name: team.name,
        id: team.id
      }
    end
    repo_list = tracked_repositories.map do |repo|
      {
        name: repo.name,
        id: repo.id
      }
    end
    reminder_json = as_json(dangerously_allow_all_keys: true)
    hydrated_reminder = reminder_json["reminder"].merge({
      org_name: remindable.login_for_api,
      org_id: remindable_id,
      description: description,
      supports_private_repos: supports_private_repos?,
      client_type: slack_workspace&.type,
      reminder_workspace_id: reminder_slack_workspace_id,
      workspace_id: slack_workspace&.slack_id,
      workspace_name: slack_workspace&.name,
      channel_name: slack_channel,
      user_id: user&.id,
      channel_id: slack_channel_id,
      reminder_text: delivery_times_text,
      delivery_times: serialize_delivery_times,
      teams: team_list,
      repos: repo_list
    })
    hydrated_reminder.except!("slack_channel", "slack_channel_id", "remindable_type", "remindable_id", "reminder_slack_workspace_id")
  end

  def set_repository_id_for_reminder_to_delete(repo_id)
    @repo_id_for_reminder = repo_id
  end

  def generate_webhook_payload
    unless defined?(@repo_id_for_reminder)
      return
    end
    action = "deleted"
    event = Hook::Event::ReminderEvent.new({
      reminder_id: self.id,
      action: action,
      actor_id: user&.id,
      event_at: Time.zone.now,
      repository_id: @repo_id_for_reminder
    })
    @delivery_system = Hook::DeliverySystem.new(event)
    @delivery_system.generate_hookshot_payloads
  end

  def instrument_destruction
    return unless defined?(@repo_id_for_reminder)
    unless defined?(@delivery_system)
      raise "`generate_webhook_payload` must be called before `instrument_destruction`"
    end

    @delivery_system.deliver_later
  end

  # Use this in feature flag checks when #user is nil
  def flipper_id
    "Reminder:#{id}"
  end

  def vexi_id
    flipper_id
  end

  def add_by_channel_id_or_name?
    case remindable
    when Organization
      remindable.feature_enabled?(:scheduled_reminders_add_by_channel_id_or_name)
    else
      false
    end
  end

  def display_name
    self[:display_name] || slack_channel
  end

  def display_name=(value)
    self[:display_name] = value
  end

end
