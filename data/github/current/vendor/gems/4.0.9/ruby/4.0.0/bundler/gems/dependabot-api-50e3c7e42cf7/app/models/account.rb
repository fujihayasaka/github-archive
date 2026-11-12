# frozen_string_literal: true

require "tzinfo"

class Account < ApplicationRecord
  T.unsafe(self).include Statesman::Adapters::ActiveRecordQueries[
    transition_class: AccountTransition,
    transition_name: :account_transition,
    initial_state: :inactive
  ]
  include FlipperActor
  include CurrentStateHelpers

  # Indicates this account has been set up with our global app capability
  GLOBAL_APP_INSTALLATION_ID = 0

  ACCOUNT_TYPES = %w(user org).freeze
  DEFAULT_INITIAL_UPDATE_RUNS_PR_LIMIT = 5

  attribute :github_login, GitHubLogin.new

  enum :event_source, { unknown: 0, webhook: 1, hydro: 2 }

  # There's only a Tenant association in Proxima envioronments
  belongs_to :tenant, optional: !Dependabot.proxima?

  has_many :repos
  has_many :repository_accesses
  has_many :registries, as: :source
  has_many :account_transitions, autosave: false
  has_many :update_configs, through: :repos, inverse_of: :account
  has_many :pull_requests, through: :repos, inverse_of: :account

  scope :active, -> { in_state(:active) }

  validates :github_id, presence: true
  validates :github_login, presence: true
  validates :account_type, inclusion: { in: ACCOUNT_TYPES }
  validates :create_merge_commits, inclusion: { in: [true, false] }
  validates :merge_on_approval, inclusion: { in: [true, false] }
  validates :current_state, inclusion: { in: AccountStateMachine.states.map(&:to_s) }

  delegate :can_transition_to?, :transition_to!, :transition_to,
           :last_transition, to: :state_machine
  delegate :shortcode, to: :tenant, allow_nil: !Dependabot.proxima?

  after_initialize :set_defaults
  after_commit :instrument_creation, on: :create

  def current_installation_id
    return if in_state?(:inactive)

    last_transition.installation_id
  end

  def active?
    !in_state?(:inactive)
  end

  def user?
    account_type == "user"
  end

  def org?
    account_type == "org"
  end

  def monolith_feature_enabled?(feature_flag, use_cache: true)
    Dependabot::Application.monolith_feature_enabled?(
      feature: feature_flag,
      actor: self,
      use_cache: use_cache
    )
  end

  # Translates this actor into a monolith object within
  # Dependabot::Application.monolith_feature_enabled?
  def monolith_actor
    @monolith_actor ||= FeatureFlags::Actor::User.new(github_id)
  end

  def tenant
    if Dependabot.proxima?
      super
    else
      NullTenant.new
    end
  end

  def self.map_account_type(github_type)
    case github_type.to_s.downcase
    when "user" then "user"
    when "organization" then "org"
    end
  end

  #######################
  # State machine setup #
  #######################

  def state_machine
    @state_machine ||=
      AccountStateMachine.new(
        self,
        association_name: :account_transitions,
        transition_class: AccountTransition
      )
  end

  def using_global_app?
    current_installation_id == GLOBAL_APP_INSTALLATION_ID || feature_enabled?(:global_tokens)
  end

  private

  def instrument_creation
    MetricsClient.increment("account.created",
                            tags: { event_source: event_source })
  end

  def set_defaults
    return unless has_attribute?(:current_state) && self[:current_state].nil?

    # set the attribute directly to avoid interactions with the state machine
    self[:current_state] = AccountStateMachine.initial_state
  end
end
