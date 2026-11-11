# typed: true
# frozen_string_literal: true

# Public: Used for determining the capabilities a default model or custom model has, based on its inherent attributes
# such as its name.
class DefaultAndCustomModels::Capabilities
  # Lowercase names of models known to belong to specific publishers. If these lists get out-of-date, the result is
  # that newer custom models by these publishers won't have all the playground capabilities they should.
  MISTRAL_AI_MODEL_NAMES = %w(codestral-2501 ministral-3b mistral-large-2411 mistral-nemo mistral-large-2407
    mistral-small mistral-medium-2505 mistral-small-2503).freeze
  OPENAI_MODEL_NAMES = %w(gpt-4.1 gpt-4.1-mini gpt-4.1-nano gpt-4o gpt-4o-mini o1 o1-mini o1-preview o3 o3-mini
    o4-mini text-embedding-3-large text-embedding-3-small).freeze
  XAI_MODEL_NAMES = %w(grok-3 grok-3-mini).freeze

  RESTRICTED_MODEL_NAMES = %w(o1 o1-mini o1-preview o3-mini o3).freeze

  # model_name - the original identifier for the model as set by its provider, e.g., "gpt-4o" or "gpt-4.1"
  # published_by_mistral_ai - whether this model was published by Mistral AI, if known
  # published_by_openai - whether this model was published by OpenAI, if known
  # published_by_xai - whether this model was published by xAI, if known
  sig do
    params(
      model_name: String,
      published_by_mistral_ai: T.nilable(T::Boolean),
      published_by_openai: T.nilable(T::Boolean),
      published_by_xai: T.nilable(T::Boolean)
    ).void
  end
  def initialize(model_name:, published_by_mistral_ai: nil, published_by_openai: nil, published_by_xai: nil)
    @model_name = model_name.downcase
    @published_by_mistral_ai = published_by_mistral_ai
    @published_by_openai = published_by_openai
    @published_by_xai = published_by_xai
  end

  sig { returns T::Boolean }
  def restricted?
    RESTRICTED_MODEL_NAMES.include?(@model_name)
  end

  sig { returns T::Boolean }
  def supports_json_schema_structured_output?
    # Currently, only GPT-4o, grok-3, and grok-3-mini support JSON Schema Structured Output
    return true if @model_name == "gpt-4o" && published_by_openai?
    if published_by_xai?
      return true if @model_name == "grok-3" || @model_name == "grok-3-mini"
    end
    false
  end

  # Public: Check if this model supports streaming responses.
  sig { returns T::Boolean }
  def supports_streaming?
    @model_name == "o3" || @model_name == "o3-mini" || !restricted?
  end

  # Public: Check if this model supports structured output.
  sig { returns T::Boolean }
  def supports_structured_output?
    # all models 'support' JSON output, but some of them are not trained on enough JSON
    # to be able to actually do it without spinning forever and outputting \n tokens
    (published_by_mistral_ai? || published_by_openai? || published_by_xai?) &&
      !restricted? # o1 models currently don't support structured output at all
  end

  sig { returns T::Boolean }
  def supports_token_counting?
    !restricted?
  end

  private

  sig { returns T::Boolean }
  def published_by_mistral_ai?
    return @published_by_mistral_ai unless @published_by_mistral_ai.nil?
    MISTRAL_AI_MODEL_NAMES.include?(@model_name)
  end

  sig { returns T::Boolean }
  def published_by_openai?
    return @published_by_openai unless @published_by_openai.nil?
    OPENAI_MODEL_NAMES.include?(@model_name)
  end

  sig { returns T::Boolean }
  def published_by_xai?
    return @published_by_xai unless @published_by_xai.nil?
    XAI_MODEL_NAMES.include?(@model_name)
  end
end
