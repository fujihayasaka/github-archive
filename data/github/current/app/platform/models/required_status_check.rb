# typed: true
# frozen_string_literal: true

class Platform::Models::RequiredStatusCheck < SimpleDelegator
  include GitHub::Relay::GlobalIdentification

  # required_status_check - A ::RequiredStatusCheck to delegate to.
  # repository - The repository this status check is relevant to
  def initialize(required_status_check, repository)
    super(required_status_check)
    @required_status_check = required_status_check
    @repository = repository
  end

  def id
    if @required_status_check.protected_branch_backed?
      @required_status_check.status_check.id
    else
      "#{@repository.id}:#{@required_status_check.rule_config.id}:#{@required_status_check.context_hash}"
    end
  end

  def repository
    @repository
  end

  def async_repository
    Promise.resolve(@repository)
  end
end
