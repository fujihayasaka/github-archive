# typed: strict
# frozen_string_literal: true
class OrchestrationStep
  Options = T.type_alias { T::Hash[Symbol, T.untyped] }

  sig { returns(Symbol) }
  attr_reader :name

  sig { returns(Options) }
  attr_reader :options

  sig { params(name: Symbol, options: Options).void }
  def initialize(name, options)
    @name = name
    @options = options
  end

  sig { returns(T::Boolean) }
  def job_start?
    !!options[:job_start]
  end

  sig { returns(T::Boolean) }
  def transaction?
    !!options[:transaction]
  end

  sig { returns(T.nilable(Integer)) }
  def max_attempts
    options[:max_attempts]
  end

  sig { returns(T::Boolean) }
  def skipped?
    !!options[:skip]
  end

  sig { returns(OrchestrationStep) }
  def self.job_start
    OrchestrationStep.new(:job_start, { job_start: true })
  end

  sig { params(name: Symbol, options: Options).returns(OrchestrationStep) }
  def self.new_step(name, options)
    OrchestrationStep.new(name, options)
  end
end
