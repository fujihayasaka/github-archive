# typed: true
# frozen_string_literal: true

class MoveWork < ApplicationRecord::Collab
  FEATURE_METADATA = {
    "protected_branches" => { icon: :"git-branch", name: "protected branches", require_paid_plan: true },
    "draft_prs" => { icon: :"git-pull-request-draft", name: "draft pull requests", require_paid_plan: true },
    "multiple_reviewers" => { icon: :people, name: "multiple reviewers", require_paid_plan: true },
    "codeowners" => { icon: :"shield-lock", name: "code owners", require_paid_plan: true },
    "roles" => { icon: :"person-fill", name: "roles", require_paid_plan: false },
    "rulesets" => { icon: :"repo-push", name: "rulesets", require_paid_plan: true },
  }.freeze

  include Workflow

  class Feature < T::Enum
    enums do
      ProtectedBranches = new("protected_branches")
      DraftPullRequests = new("draft_prs")
      MultipleReviewers = new("multiple_reviewers")
      CodeOwners = new("codeowners")
      Roles = new("roles")
      Rulesets = new("rulesets")
    end

    def supported_by_plan?(plan)
      case self
      when Roles
        true # it is supported by any org plan
      when MultipleReviewers
        plan.limit(:manual_review_requests, visibility: :private, org: true) > 1
      else
        plan.supports?(self.serialize.to_sym, visibility: :private, org: true)
      end
    end

    def name
      metadata[:name]
    end

    def metadata
      MoveWork::FEATURE_METADATA[self.serialize]
    end

  end

  enum :feature, {
    Feature::ProtectedBranches.serialize => 0,
    Feature::DraftPullRequests.serialize => 1,
    Feature::MultipleReviewers.serialize => 2,
    Feature::CodeOwners.serialize => 3,
    Feature::Roles.serialize => 4,
    Feature::Rulesets.serialize => 5,
  }, prefix: true

  workflow :state do
    state :created, 0 do
      event :start, transitions_to: :started
    end

    state :started, 1 do
      event :complete, transitions_to: :completed
    end

    state :completed, 2

    after_transition do |_from, to, _event, *_args, **_kwargs|
      T.bind(self, MoveWork)
      ::MoveWork::MoveResourcesJob.perform_later(self) if to == :started
    end
  end

  belongs_to :user
  belongs_to :origin, class_name: "User"
  belongs_to :target, class_name: "Organization"

  has_many :move_work_items, dependent: :destroy

  validates :origin, presence: true
  validates :state, presence: true
  validates :target, presence: true
  validates :user, presence: true
  validate :target_must_be_owned_by_user

  # Returns the total number of items that are being moved grouped by resource type.
  #
  # eg: #=> { "Repository" => 2, "Project" => 1 }
  sig { returns(T::Hash[String, Integer]) }
  def total_items_by_resource_type
    @total_items_by_resource_type ||= T.let(
      move_work_items.group(:resource_type).count,
      T.nilable(T::Hash[String, Integer]),
    )
  end

  sig { params(owner: User, resource: T.any(Repository, Project)).returns(T::Boolean) }
  def self.started_for?(owner, resource)
    joins(:move_work_items)
      .where(origin: owner, state: state_value(:started))
      .where(move_work_items: { resource: resource })
      .exists?
  end

  sig { params(name: T.any(String, Symbol)).returns(Integer) }
  def self.state_value(name)
    workflow_spec.states[name.to_sym].value
  end

  def feature
    Feature.try_deserialize(self.attributes["feature"])
  end

  private

  sig { void }
  def target_must_be_owned_by_user
    errors.add(:target, "must be adminable by user") unless target&.adminable_by?(user)
  end
end
