# typed: true
# frozen_string_literal: true

class CodeScanning::Settings::RunnerInfoComponent < ApplicationComponent
  attr_reader :repository

  sig { params(repository: T.any(Repository, T::Struct), runner_label: T.nilable(String), failed_to_load: T::Boolean).void }
  def initialize(repository:, runner_label: nil, failed_to_load: false)
    @repository = repository
    @failed_to_load = failed_to_load
    @runner_label = runner_label
  end

  private

  sig { returns(T::Boolean) }
  def auto_codeql_runner_label_error?
    @failed_to_load
  end

  sig { returns(T.nilable(String)) }
  def autocodeql_runner_label
    @runner_label.presence
  end
end
