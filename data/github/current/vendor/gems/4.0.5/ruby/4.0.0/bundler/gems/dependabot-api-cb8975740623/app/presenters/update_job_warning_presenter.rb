# frozen_string_literal: true

class UpdateJobWarningPresenter
  include PresenterHelper

  DEFAULT_WARNING_DESCRIPTION = "Dependabot has detected a warning. See the logs for more details."

  def initialize(warning_hash:, update_job:)
    @warning_hash = warning_hash
    @update_job = update_job
  end

  def issue_type
    sanitize_input(warn_type)
  end

  def issue_title
    sanitize_input(warn_title)
  end

  def issue_body
    value = sanitize_input(warn_description)
    value.presence || DEFAULT_WARNING_DESCRIPTION
  end

  attr_reader :warning_hash, :update_job

  private

  def warn_type
    warning_hash.fetch("warn_type")
  end

  def warn_title
    warning_hash.fetch("warn_title")
  end

  def warn_description
    warning_hash.fetch("warn_description")
  end
end
