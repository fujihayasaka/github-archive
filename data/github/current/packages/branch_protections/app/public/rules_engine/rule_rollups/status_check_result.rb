# typed: strict
# frozen_string_literal: true

class RulesEngine::RuleRollups::StatusCheckResult

  sig { returns(Repository) }
  attr_reader :repository

  sig { returns(String) }
  attr_reader :context

  sig { returns(T.nilable(Integer)) }
  attr_reader :integration_id

  sig { returns(String) }
  attr_reader :result

  sig { params(repository: Repository, context: String, integration_id: T.nilable(Integer), result: String).void }
  def initialize(repository, context, integration_id, result)
    @repository = repository
    @context = context
    @integration_id = integration_id
    @result = result
  end

  class Payload < T::Struct
    const :context, String
    const :integrationId, T.nilable(Integer)
    const :result, String
  end

  sig { returns(Promise[Repository]) }
  def async_repository
    Promise.resolve(repository)
  end

  sig { returns(Promise[T.nilable(Integration)]) }
  def async_integration
    Platform::Loaders::ActiveRecord.load(Integration, integration_id)
  end

  sig { returns(Payload) }
  def payload
    Payload.new(
      context: context,
      integrationId: integration_id,
      result: result
    )
  end

end
