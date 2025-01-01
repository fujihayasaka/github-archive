# typed: true
# frozen_string_literal: true

class RequiredDeployment < ApplicationRecord::Domain::Repositories
  include Instrumentation::Model
  include GitHub::Validations

  belongs_to :protected_branch

  validates :environment, presence: true, unicode3: true

  after_create_commit :instrument_create
  after_destroy_commit :instrument_destroy

  private

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
      :environment => environment,
    }

    if repo && repo.in_organization?
      payload[:org] = repo.organization
    end

    payload
  end
end
