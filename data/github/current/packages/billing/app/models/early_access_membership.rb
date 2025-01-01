# typed: strict
# frozen_string_literal: true

# Keeps track of membership in an early access waitlist for new features.
class EarlyAccessMembership < ApplicationRecord::Domain::Users
  extend T::Sig

  include GitHub::Relay::GlobalIdentification

  # Organizations can also be members but polymorphic associations for STI models use their base class
  # (see Polymorphic Associations section on STI: https://api.rubyonrails.org/classes/ActiveRecord/Associations/ClassMethods.html)
  # This model has another attribute to distinguish between the User models called `member_class_name`
  VALID_MEMBER_TYPES = T.let(%w(User Business MemexProject), T::Array[String])
  FEATURE_CHECK_TTL = 30

  MULTIPLE_MEMBER_NOMINATION_FEATURES = T.let(%w(hierarchy_and_roadmap copilot_for_enterprise copilot_customization), T::Array[String])

  # Public: The User, Organization, or Business that has signed up for the early
  # access waitlist.
  belongs_to :member, polymorphic: true, foreign_key: "member_id"
  validates_presence_of :member
  validates :member_type, presence: true, inclusion: { in: VALID_MEMBER_TYPES }
  validates_uniqueness_of :member_id,
    scope: [:member_type, :feature_slug],
    conditions: -> { where.not(feature_slug: %w[copilot_for_enterprise copilot_customization copilot_extension_access]) }

  # Public: The User that signed up for early access. For individuals this will
  # always be equal to user. For Organizations or Businesses, this is the User
  # that performed the registration for the org/enterprise account.
  belongs_to :actor, class_name: "User"
  validates_presence_of :actor
  validate :actor_must_be_a_user

  # due to the fact that users may not always be admins for organizations or
  # businesses, we should only run this validation when creating the record,
  # as always enforcing this restricts the ability for stafftools to update
  # this record
  validate :actor_can_admin_user, on: :create

  # Public: The survey to be filled out as part of signing up for early access.
  belongs_to :survey
  validates_presence_of :survey

  # Public: Unique slug for the name of the feature for which the member is on
  # the waitlist.
  validates_presence_of  :feature_slug
  validates_inclusion_of(
    :feature_slug,
    in: %w[
      github_sponsors
      mobile_preview_waitlist
      okta_team_sync
      reminders
      team_sync
      testing_only
      workspaces
      codespaces_vs2019
      projects_vnext
      memex_table_without_limits
      blackbird_fe
      code_search_code_view
      merge_queue
      copilot_for_business
      custom_hosted_runners
      hierarchy_and_roadmap
      octoshift_bitbucket_server
      projects_tasklist
      projects_roadmap_layout
      copilot_for_enterprise
      copilot_customization
      copilot_chat_jetbrains
      copilot_extension_access
      copilot_next_edit_suggestions
      copilot_workspace
      project_neutron_playground
    ],
  )

  before_create :set_member_class_name

  # Public: Early access waitlist for GitHub Sponsors.
  scope :sponsors_waitlist, -> { where(feature_slug: "github_sponsors") }

  # Public: Early access waitlist for GitHub team synchronization.
  scope :team_sync_waitlist, -> { where(feature_slug: "team_sync") }

  # Public: Early access waitlist for GitHub team synchronization.
  scope :okta_team_sync_waitlist, -> { where(feature_slug: "okta_team_sync") }

  # Public: Early access waitlist for GitHub larger runners. Note: cannot rename to official Larger Runners as it would break history
  scope :custom_hosted_runners_waitlist, -> { where(feature_slug: "custom_hosted_runners") }

  # Public: Early access waitlist for Scheduled reminders.
  scope :reminders_waitlist, -> { where(feature_slug: "reminders") }

  # Public: Early access waitlist for GitHub mobile beta
  scope :mobile_beta_waitlist, -> { where(feature_slug: "mobile_preview_waitlist") }

  # Public: Early access waitlist for Workspaces
  scope :copilot_for_business_waitlist, -> { where(feature_slug: "copilot_for_business") }

  # Public: Early access waitlist for Workspaces
  scope :workspaces_waitlist, -> { where(feature_slug: "workspaces") }

  # Public: Early access waitlist for Projects vNext
  scope :projects_vnext_waitlist, -> { where(feature_slug: "projects_vnext") }

  # Public: Early access waitlist for Blackbird Code Search
  scope :blackbird_waitlist, -> { where(feature_slug: "blackbird_fe") }

  # Public: Early access waitlist for Code Search + Code View in github.com
  scope :code_search_code_view_waitlist, -> { where(feature_slug: "code_search_code_view") }

  # Public: Early access waitlist for Merge Queue
  scope :merge_queue_waitlist, -> { where(feature_slug: "merge_queue") }

  # Public: filter early access memberships to those (at the time of the request) from organizations
  # fun fact: users can request access to things then later convert to an organization
  scope :organizations, -> { where(member_class_name: "Organization") }

  # Public: Early access waitlist for Memex Hierarchy and Roadmap
  scope :hierarchy_and_roadmap_waitlist, -> { where(feature_slug: "hierarchy_and_roadmap") }

  # Private: Early access wait list for hierarchy only
  # These records are generated from the main hierarchy_and_roadmap  wait list
  scope :projects_tasklist_waitlist, -> { where(feature_slug: "projects_tasklist") }

  # Private: Early access wait list for memex without limits
  scope :memex_without_limits_waitlist, -> { where(feature_slug: "memex_table_without_limits") }

  # Private: Early acces wait list for Bitbucket Migrator
  scope :bitbucket_server_migrations_waitlist, -> { where(feature_slug: "octoshift_bitbucket_server") }

  # Private: Early access waitlist for the CfE SKU
  scope :copilot_for_enterprise_waitlist, -> { where(feature_slug: "copilot_for_enterprise") }

  # Private: Early access waitlist for copilot extensions
  scope :copilot_extensions_waitlist, -> { where(feature_slug: "copilot_extension_access") }

  # Private: Early access waitlist for Copilot fine-tuning
  scope :copilot_customization_waitlist, -> { where(feature_slug: "copilot_customization") }

  # Private: Early access waitlist for Copilot Chat in Jetbrains IDEs
  scope :copilot_chat_jetbrains_waitlist, -> { where(feature_slug: "copilot_chat_jetbrains") }

  scope :copilot_next_edit_suggestions_waitlist, -> { where(feature_slug: "copilot_next_edit_suggestions") }

  scope :copilot_workspace_waitlist, -> { where(feature_slug: "copilot_workspace") }

  scope :project_neutron_playground_waitlist, -> { where(feature_slug: "project_neutron_playground") }

  scope :with_member_login, -> (login) {
    joins("INNER JOIN users on users.id = early_access_memberships.member_id")
      .and(User.where(login: login))
  }

  scope :with_business_member_slug, -> (slug) {
    joins("INNER JOIN businesses on businesses.id = early_access_memberships.member_id")
      .and(Business.where(slug: slug))
  }

  # Public: Is the member on the waitlist for the feature with the
  # specified slug?
  sig { params(feature_slug: T.any(String, Symbol), account: ::Billing::Types::Account).returns(T::Boolean) }
  def self.on_waitlist?(feature_slug, account)
    exists?(feature_slug: feature_slug, member: account)
  end

  # Public: Is the member on the waitlist for the feature with the
  # specified slug and granted access?
  sig { params(feature_slug: T.any(String, Symbol), account: ::Billing::Types::Account).returns(T::Boolean) }
  def self.member_enabled?(feature_slug, account)
    return false unless account.is_a?(User) || account.is_a?(Business)

    ActiveRecord::Base.connected_to(role: :reading) do
      where(
        member: account,
        feature_slug: feature_slug,
        feature_enabled: true
      ).exists?
    end
  end

  # Public: Returns a cache key for the provided feature and user.
  # This is used by flipper to cache the results of a member_enabled?
  # to avoid re-querying on every enabled? check.
  sig { params(feature_slug: T.any(String, Symbol), account: ::Billing::Types::Account).returns(String) }
  def self.member_enabled_key(feature_slug, account)
    "early_access_membership:#{feature_slug}:#{account.class}:#{account.id}"
  end

  # Public: Has this account already answered the waitlist survey for the
  # specified feature? Surveys can be filled out personally or on behalf of an
  # organization or enterprise account. Each individual should only answer a
  # survey once.
  sig { params(feature_slug: T.any(String, Symbol), actor: T.nilable(::User)).returns(T::Boolean) }
  def self.answered_survey?(feature_slug, actor)
    return false unless actor

    exists?(feature_slug: feature_slug, actor_id: actor.id)
  end

  # Allows for scoping by members of different classes because Rails sets
  # `member_type` to the shared base class for STI models
  sig { returns(String) }
  def set_member_class_name
    self.member_class_name = self.member.class.name
  end

  # Public: Save a list of answers to survey questions as part of early access
  # registration.
  #
  # answers - Array of Hashes in the form:
  #          [{:question_id => 1, :choice_id => 2, :other_text => ""}, ...]
  sig { params(answers: T.nilable(T::Array[T::Hash[Symbol, T.untyped]])).returns(T::Boolean) }
  def save_with_survey_answers(answers)
    #
    # An admin may request access to a feature for multiple organizations, and if we exit early we do not track
    # which features were requested for the 2nd or later orgs
    #
    # This opts the Hierarchy and Roadmap signup page out of skipping this stage, and will look at the survey answers
    # for each organization they wish to sign up.
    #
    if self.class.answered_survey?(feature_slug, actor) && !MULTIPLE_MEMBER_NOMINATION_FEATURES.include?(feature_slug)
      return save
    end

    answers ||= []
    actor = T.must(self.actor)
    survey = T.must(self.survey)

    survey_answers = answers.map do |answer|
      SurveyAnswer.new \
        user_id: actor.id,
        survey_id: survey.id,
        question_id: answer[:question_id],
        choice_id: answer[:choice_id],
        other_text: answer[:other_text]
    end

    #
    # For the Hierarchy and Roadmap signup page we wish to persist the details about the survey because we cannot
    # link back to these for a given EarlyAccessMembership record once the SurveyAnswer records are persisted. This
    # will cause us to lose the context when a user requests access for multiple organizations.
    #
    # This is only something we've enabled to support a single signup page driving several features, and without this
    # context the onboarding experience would not be what the user expected.
    #
    # This custom code will be discarded once the signup page is no longer necessary, so please do not rely on this
    # for other signup pages.
    #
    if feature_slug == "hierarchy_and_roadmap"
      PlanningTrackingSurveyResult.store_survey_results(self, survey_answers)
    end

    if Rails.env.development? || (survey_answers.size > 0 && survey_answers.all?(&:valid?))
      transaction do
        survey_answers.each(&:save!)
        save
      end
    else
      errors.add(:base, "all questions are required")
      false
    end
  end

  private

  sig { void }
  def actor_must_be_a_user
    actor = self.actor
    unless actor && actor.user?
      errors.add(:actor, "must be a user")
    end
  end

  sig { void }
  def actor_can_admin_user
    return unless can_onboard
    return if feature_slug == "workspaces" || feature_slug == "custom_hosted_runners"
    return unless actor && member
    if member.is_a?(Business) && !member.adminable_by?(actor)
      errors.add(:actor, "must be an owner to register enterprise")
    elsif member.is_a?(Organization) && member.organization? && !member.adminable_by?(actor)
      errors.add(:actor, "must be an admin to register organization")
    elsif member.is_a?(User) && member.user? && member != actor
      errors.add(:actor, "can only register their own user")
    end
  end
end
