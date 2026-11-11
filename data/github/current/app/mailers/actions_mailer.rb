# typed: true
# frozen_string_literal: true

class ActionsMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/actions"
  helper :bundle
  helper :mailer_bundle

  layout "layouts/primer_layout"

  def example_email(user)
    @user = user
    @subject = "[GitHub] Actions email example"
    @footer_text = "You are receiving this email because you are a really special person ♥️"

    premail(
      from: github_noreply,
      to: user_email(user),
      subject: @subject
    )
  end

  def workflow_inactivity(user, workflow, disabled: false)
    @workflow = workflow
    @repo = workflow.repository
    @user = user
    message = disabled ? "has been disabled" : "will be disabled soon"
    @subject = "[GitHub] The \"#{@workflow.name}\" workflow in #{@repo.name_with_display_owner} #{message}"
    @footer_text = "You are receiving this because you are the owner of the #{@repo.name_with_display_owner} repository."
    @threshold = Actions::Workflow::REPOSITORY_INACTIVITY_THRESHOLD
    @url = workflow_runs_list_url(user_id: @repo.owner.display_login, repository: @repo, workflow_file_name: @workflow.filename)
    @disabled = disabled
    email = user_email(user)
    if email.present?
      premail(
        from: github_noreply,
        to: email,
        subject: @subject
      )
    end
  end
end
