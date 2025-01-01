# typed: strict
# frozen_string_literal: true

class CodeQualityEnablement < SecurityProduct::Service
  sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def can_enable?(actor:, options:)
    return SecurityProduct::Result.new(false, :not_part_of_preview) unless repository.owner&.feature_flag_enabled?(:code_quality, default: false) || repository.feature_flag_enabled?(:code_quality, default: false)
    return SecurityProduct::Result.new(false, :auto_codeql_not_enabled) unless auto_codeql.enabled?(feature: :CODE_QUALITY)
    SecurityProduct::Result.new(true)
  end

  sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def can_disable?(actor:, options:)
    SecurityProduct::Result.new(true)
  end

  sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def on_enable(actor:, options:)
    result = auto_codeql.on_enable(
      actor:,
      options: {
        feature: :CODE_QUALITY,
        action: :update,
        code_quality_enabled: Turboscan::Proto::UpdateRequest::CodeQualityEnablement::CODE_QUALITY_ENABLED
      }
    )
    if result.error?
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, result.error)
    else
      publish_instrumentation(enabled: true)
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end
  end

  sig { override.params(actor: User, options: T.untyped).returns(SecurityProduct::Result) }
  def on_disable(actor:, options:)
    result = auto_codeql.on_enable(
      actor:,
      options: {
        feature: :CODE_QUALITY,
        action: :update,
        code_quality_enabled: Turboscan::Proto::UpdateRequest::CodeQualityEnablement::CODE_QUALITY_DISABLED
      }
    )
    if result.error?
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.empty, result.error)
    else
      publish_instrumentation(enabled: false)
      SecurityProduct::Result.new(SecurityProduct::ToggledServiceCollection.create(to_sym, options))
    end
  end

  sig { override.returns(T::Boolean) }
  def enabled?
    return false if repository.deleted?

    if (
      repository.feature_flag_enabled?(:code_quality_pass_feature_param, default: false) ||
      repository.owner&.feature_flag_enabled?(:code_quality_pass_feature_param, default: false)
    )
      return auto_codeql.enabled?(feature: :CODE_QUALITY)
    end

    # code_quality_enabled is a field designed for use in a setup where Code Quality
    # is building off Default Setup rather than set up as a feature in its own right.
    # Where Code Quality is set up as a feature in its own right, we can check the regular
    # enabled? method (passing in the feature param) as we do above.
    #
    # Although we pass the feature here, it'll actually be ignored since the
    # code_quality_pass_feature_param flag is off, but it makes sense not to
    # "pre-judge" that and to pass it anyway.
    #
    # Once the flag is fully rolled out, we can always return the result of the call in
    # the if statement above and this line below can go.
    auto_codeql.configuration(feature: :CODE_QUALITY).code_quality_enabled
  end

  sig { override.returns(Symbol) }
  def to_sym
    :code_quality
  end

  sig { override.returns(String) }
  def self.name
    "Code quality"
  end

  sig { override.params(symbol: T.nilable(SecurityProduct::Result::Error)).returns(String) }
  def self.error_to_message(symbol)
    case symbol
    when :not_part_of_preview
      "This organization is not part of the code quality preview."
    when :auto_codeql_not_enabled
      "Code Scanning default setup is not enabled on this repository."
    else
      super
    end
  end

  private

  sig { returns(CodeScanning::AutoCodeql) }
  def auto_codeql
    CodeScanning::AutoCodeql.new(repository)
  end

  sig { params(enabled: T::Boolean).void }
  def publish_instrumentation(enabled:)
    GlobalInstrumenter.instrument(
      "code_quality.toggled",
      repository_id: repository.id,
      feature_enabled: enabled,
    )
  end
end
