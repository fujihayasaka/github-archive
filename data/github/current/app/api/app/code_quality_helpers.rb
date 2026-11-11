# typed: strict
# frozen_string_literal: true

module Api::App::CodeQualityHelpers
  extend T::Helpers
  requires_ancestor { Api::App }

  sig { params(repo: Repository, forbid: T::Boolean).void }
  def ensure_read_access_and_code_quality_enabled!(repo, forbid: false)
    can_read = access_allowed? :v4_get_repo,
                                resource: repo,
                                repo: repo,
                                allow_integrations: true,
                                allow_user_via_granular_actor: true

    deliver_error!(forbid ? 403 : 404) if !can_read

    ensure_code_quality_available!(repo)
    ensure_code_quality_enabled!(repo)
  end

  sig { params(finding_number: Integer).void }
  def ensure_valid_finding_number!(finding_number)
    deliver_error!(422, message: "finding_number must be greater than zero") if finding_number < 1
  end

  sig { void }
  def ensure_non_conflicting_cursor_params!
    if params.key?(:after) && params.key?(:before)
      deliver_error!(400, message: "Please do not provide both 'before' and 'after' parameters.")
    end
  end

  sig { returns(T.noreturn) }
  def deliver_code_quality_unavailable_error!
    deliver_error!(503, message: "Code quality unavailable. Please try again later.")
  end

  sig { returns(String) }
  def code_quality_forbid_read_message
    "You are not authorized to view code quality findings."
  end

  private

  sig { params(repo: Repository).void }
  def ensure_code_quality_available!(repo)
    if !CodeQuality.available?(repo)
      deliver_error!(404)
    end
  end

  sig { params(repo: Repository).void }
  def ensure_code_quality_enabled!(repo)
    if !CodeQuality.enabled?(repo)
      deliver_error!(403, message: code_quality_disabled_message)
    end
  end

  sig { returns(String) }
  def code_quality_disabled_message
    if GitHub.enterprise?
      "Code quality is not enabled. Please contact your local GitHub Enterprise site administrator for assistance."
    else
      "Code quality is not enabled for this repository. Please enable code quality in the repository settings."
    end
  end
end
