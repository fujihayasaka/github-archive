# typed: true
# frozen_string_literal: true

class Checks::RetentionComponent < ApplicationComponent
  def initialize(check_suite:, is_actions: false)
    @check_suite = check_suite
    @is_actions = is_actions
  end

  def render?
    @check_suite.is_archived?
  end

  def notice_text
    return "This run and associated checks have been archived and are scheduled for deletion." if @is_actions
    "This check has been archived and is scheduled for deletion."
  end

  def docs_link
    "#{GitHub.help_url}/rest/guides/getting-started-with-the-checks-api#retention-of-checks-data"
  end
end
