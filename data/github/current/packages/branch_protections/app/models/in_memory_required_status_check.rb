# typed: true
# frozen_string_literal: true

class InMemoryRequiredStatusCheck
  include ActiveModel::Model

  sig do params(
    rule_config: RepositoryRuleConfiguration,
    required_status_checks: T::Enumerable[T.any(RequiredStatusCheck, T::Hash[String, T.untyped])])
    .returns(T::Array[InMemoryRequiredStatusCheck])
  end
  def self.normalize_status_checks(rule_config, required_status_checks)
    required_status_checks.map do |status_check|
      if status_check.is_a?(RequiredStatusCheck)
        InMemoryRequiredStatusCheck.new(rule_config, status_check.context, status_check: status_check)
      else
        InMemoryRequiredStatusCheck.new(rule_config, status_check["context"], integration_id: status_check["integration_id"])
      end
    end
  end

  sig { returns(String) }
  attr_reader :context

  sig { returns(RepositoryRuleConfiguration) }
  attr_reader :rule_config

  sig { returns(T.nilable(RequiredStatusCheck)) }
  attr_reader :status_check

  sig { returns(T.nilable(Integer)) }
  attr_reader :integration_id

  delegate :source, to: :@rule_config

  sig { params(rule_config: RepositoryRuleConfiguration, context: String, status_check: T.nilable(RequiredStatusCheck), integration_id: T.nilable(Integer)).void }
  def initialize(rule_config, context, status_check: nil, integration_id: nil)
    @rule_config = rule_config
    @context = context
    @status_check = status_check
    @integration_id = integration_id || status_check&.integration_id
  end

  def protected_branch_backed?
    @status_check.present?
  end

  def async_protected_branch
    @status_check&.async_protected_branch
  end

  def integration
    return @integration if defined?(@integration)
    return @status_check.integration if @status_check
    return nil unless integration_id

    @integration = Integration.find(T.must(integration_id))
  end

  def [](key)
    if key.to_sym == :context
      context
    end
  end

  # Generates a hash based on the context and integration_id
  # This is used to create a unique ID for the status check (scoped to a RepositoryRuleConfiguration)
  # and allowed it to be queried from GraphQL
  def context_hash
    InMemoryRequiredStatusCheck.generate_context_hash(context, integration_id)
  end

  def self.generate_context_hash(context, integration_id)
    Digest::SHA256.hexdigest("context:#{context};integration_id:#{integration_id}")
  end

  ###
  # The follow methods are needed for GlobalIdentification
  ###

  def platform_type_name
    "RequiredStatusCheck"
  end

  def created_at
    return @status_check.created_at if @status_check
    rule_config.created_at || Time.now
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
    "Waiting for status to be reported"
  end

  def contextual_name
    context
  end
end
