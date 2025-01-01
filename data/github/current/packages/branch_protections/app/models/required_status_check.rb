# typed: true
# frozen_string_literal: true

# Required status checks are in support of Protected Branches.
# See ProtectedBranch class for more # information.
#
# The existence of a protected branch status for a status context indicates
# that a successful context must be associated with the commit to update the
# target branch.
class RequiredStatusCheck < ApplicationRecord::Repositories
  include GitHub::UTF8
  include GitHub::Validations
  include Instrumentation::Model

  MAXIMUM_CONTEXT_BYTESIZE = 1020

  belongs_to :protected_branch
  belongs_to :integration

  delegate :repository, to: :protected_branch

  # https://github.com/github/data-partitioning/issues/540
  attribute :context, StringFromBinary.new

  validates :protected_branch_id, presence: true
  validates :context, presence: true, bytesize: { maximum: MAXIMUM_CONTEXT_BYTESIZE },
    unicode: true, uniqueness: { scope: :protected_branch_id, case_sensitive: true }
  validate :limit_statuses, on: :create

  after_create_commit :instrument_create
  after_destroy_commit :instrument_destroy

  # The maximum number of RequiredStatusChecks allowed per ProtectedBranch.
  MAX_PER_BRANCH = Status::MAX_PER_SHA_AND_CONTEXT

  # Description of expected status in the merge box.
  DESCRIPTION = "Waiting for status to be reported"

  sig { params(required: T::Enumerable[RequiredStatusCheck]).returns(T::Hash[String, T::Set[Integration]]) }
  def self.pluck_contexts_and_integrations(required)
    rows = required.pluck(:context, :integration_id)

    integration_ids = rows.map { |_, integration_id| integration_id }
    integrations = Integration.where(id: integration_ids).includes(:bot).group_by(&:id)

    rows.each_with_object({}) do |(context, integration_id), results|
      results[context] ||= Set.new
      results[context].merge(integrations.fetch(integration_id, []))
    end
  end

  def async_repository
    async_protected_branch.then do |protected_branch|
      T.must(protected_branch).async_repository
    end
  end

  def protected_branch_backed?
    true
  end

  ###
  # The following methods provide a StatusCheck ducktype
  ###

  def duration_in_seconds
    0
  end

  def required_for_pull_request?(pull)
    async_required_for_pull_request?(pull).sync
  end

  def async_required_for_pull_request?(pull)
    Promise.resolve(true)
  end

  def application
    nil
  end

  def creator
    nil
  end

  def target_url(pull_request_number: nil)
    nil
  end

  def state
    StatusCheckConfig::EXPECTED
  end

  def state_changed_at
    Time.now
  end

  def sort_order
    [CheckRun::MAX_NUMBER_VALUE, StatusCheckConfig::STATE_SORT_ORDER[state], context]
  end

  def description
    DESCRIPTION
  end

  def contextual_name
    context
  end

  private

  # Private: Validation to limit the number of RequiredStatusCheck's per ProtectedBranch
  #
  # Returns nothing.
  def limit_statuses
    if protected_branch_limit_reached?
      errors.add :base, "maximum number of status contexts for this branch reached"
    end
  end

  # Private: Returns Boolean indicating if we have reached the limit of RequiredStatusChecks
  def protected_branch_limit_reached?
    self.class.where(protected_branch_id: protected_branch_id).count >= MAX_PER_BRANCH
  end

  # Private: Instrument creation of this ProtectedBranch
  def instrument_create
    instrument :create
  end

  # Private: Instrument deletion of this record with the actor who did it
  def instrument_destroy
    instrument :destroy
  end

  def event_payload
    repo = protected_branch&.repository

    payload = {
      event_prefix => self,
      :protected_branch_id => protected_branch_id,
      # protected_branch can be nil in the case of cascading destroys
      :protected_branch_name => protected_branch&.name,
      :repo => repo,
      :context => context,
    }

    if repo && repo.in_organization?
      payload[:org] = repo.organization
    end

    payload
  end
end
