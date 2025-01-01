# typed: strict
# frozen_string_literal: true

module Api::App::ActionsVariablesHelpers
  extend T::Sig
  extend T::Helpers
  requires_ancestor { Api::App }

  sig { params(block: T.proc.void).returns(T.untyped) }
  def rescue_from_variables_errors(&block)
    yield
  rescue Variables::Error => e
    if e.options.present?
      deliver_error!(e.status, e.options)
    else
      deliver_error!(e.status)
    end
  end

  sig { params(result: T.untyped).returns(T.untyped) }
  def validate_result!(result)
    unless result
      Failbot.report(StandardError.new("no response from store_variable"), kredz: GitHub.kredz)
      deliver_error!(503, message: "Variables unavailable. Please try again later.")
    end
  end

  sig { params(result: T.untyped).returns(T.untyped) }
  def validate_storage!(result)
    unless result.stored
      Failbot.report(StandardError.new("store_variable did not store"), kredz: GitHub.kredz)
      deliver_error!(500, message: "Variable was not stored")
    end
  end

  sig { params(result: T.untyped).returns(T.untyped) }
  def validate_update!(result)
    unless result.updated
      Failbot.report(StandardError.new("update_variable did not update"), kredz: GitHub.kredz)
      deliver_error!(500, message: "Variable was not updated")
    end
  end

  sig { params(result: T.untyped).returns(T.untyped) }
  def validate_listing!(result)
    unless result
      Failbot.report(StandardError.new("no response from list"), kredz: GitHub.kredz)
      deliver_error!(503, message: "Variables unavailable. Please try again later.")
    end
  end

  sig { params(variable: T.untyped).returns(T::Array[String]) }
  def map_selected_repo_global_ids(variable)
    variable.selected_repositories.map do |repo|
      Platform::Helpers::NodeIdentification.from_global_id(repo.global_id)[1].to_s
    end
  end
end
