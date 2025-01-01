# typed: true
# frozen_string_literal: true

class RepositoryMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  self.mailer_name = "mailers/repository"

  helper :avatar
  helper :octicons
  helper Primer::ViewHelper
  layout "repository/collab_email_layout", only: [:collab_invited]

  def private_repository_deleted(repository)
    @repository_name = repository.name_with_display_owner

    mail(
      to: user_email(repository.owner),
      subject: "#{repository.name_with_display_owner} deleted",
    )
  end

  def private_fork_deleted(repo_nwo:, parent_nwo:, repo_owner:)
    @repository_name = repo_nwo
    @parent_repo_name = parent_nwo

    mail(
      to: user_email(repo_owner),
      subject: "fork of #{@parent_repo_name} has been deleted",
    )
  end

  def collab_invited(invitation)
    invitation.reset_token
    @invitation = invitation
    @inviter = invitation.inviter
    @invitee = invitation.invitee
    @email = invitation.email? ? invitation.email : @invitee.email
    @repository = invitation.repository
    @signature = notification_signature(@repository.permalink)
    invitation_context = if invitation.sponsors_only_repository_invitation?
      "For sponsors only: "
    end

    email = GitHub.newsies.settings(@invitee).email(@repository.organization || :global).address if @invitee.present?

    premail(
      from: github_noreply(@inviter),
      to: @email,
      subject: "#{invitation_context}#{@inviter} invited you to #{@repository.name_with_display_owner}",
    )
  end

  # Sent to all non-suspended, non-opted-out org admins when a deploy key is added to a repository.
  def deploy_key_added(key)
    @key = key
    repository_owner = key.repository.owner
    opted_out_admins = if repository_owner.is_a?(Organization)
      repository_owner.admins.reject do |admin|
        GitHub.newsies.settings(admin).org_deploy_key_email?
      end
    else
      []
    end

    recipients = user_or_admin_recipients(repository_owner, except: opted_out_admins)

    mail(
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: "[GitHub] A new public key was added to #{key.repository.name_with_display_owner}",
    )
  end

  # Sent to all org admins when a deploy key is updated.
  def deploy_key_updated(key)
    @key = key
    recipients = user_or_admin_recipients(key.repository.owner)

    mail(
      to: recipients[:to],
      bcc: recipients[:bcc],
      subject: "[GitHub] A public key associated with #{key.repository.name_with_display_owner} was updated",
      template_name: "deploy_key_added",
    )
  end

  def dmca_takedown_notice(repository, url)
    @repository = repository
    @takedown_url = url
    recipients = user_or_admin_recipients(repository.owner)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] DMCA takedown notice for #{repository.name_with_display_owner}",
    )
  end

  def country_block_notice(repository, block, url)
    @repository = repository
    @country_block_description = GitRepositoryBlock::COUNTRY_BLOCK_DESCRIPTIONS[block]
    @country_block_url = url
    @countries = GitRepositoryBlock::COUNTRY_BLOCK_TYPES[block]
    recipients = user_or_admin_recipients(repository.owner)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Repository blocked in certain countries",
    )
  end

  def admin_disabled_notice(repository, instructions = nil)
    @repository = repository
    @instructions = instructions
    recipients = user_or_admin_recipients(repository.owner)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Repository access disabled for #{repository.name_with_display_owner}",
    )
  end

  def size_disabled_notice(repository, instructions = nil, template: nil)
    recipients = user_or_admin_recipients(repository.owner)

    template ||= \
      if GitHub.enterprise?
        Stafftools::Repository::DISABLE_TEMPLATE_FOR_SIZE_ENTERPRISE
      else
        Stafftools::Repository::DISABLE_TEMPLATE_FOR_SIZE_DOT_COM
      end
    variables = {
      repository_name_with_owner: repository.name_with_display_owner,
      is_github_enterprise: GitHub.enterprise?,
      instructions: instructions.to_s,
      github_help_url: "<a href=\"#{GitHub.help_url}/articles/github-acceptable-use-policies\">GitHub's Acceptable Use Policies</a>",
      github_appeal_reinstatement_docs_url: "<a href=\"#{GitHub.help_url}/articles/github-appeal-and-reinstatement\">Appeal and Reinstatement Policy</a>",
      reinstatement_request_form_url: "<a href=\"#{GitHub.contact_support_url}/reinstatement\">form</a>",
      contact_support_url: "<a href=\"#{GitHub.contact_support_url}\">contact GitHub Support</a>",
    }

    mail(
      content_type: "text/html",
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Repository access disabled for #{repository.name_with_display_owner}",
      body: Mustache.render(template, variables),
    )
  end

  def tos_disabled_notice(repository, instructions = nil, template: nil)
    recipients = user_or_admin_recipients(repository.owner)

    template ||= Stafftools::Repository::DISABLE_TEMPLATE_FOR_TOS
    variables = {
      repository_name_with_owner: repository.name_with_display_owner,
      github_appeal_reinstatement_docs_url: "<a href=\"#{GitHub.help_url}/articles/github-appeal-and-reinstatement\">Appeal and Reinstatement Policy</a>",
      reinstatement_request_form_url: "<a href=\"#{GitHub.contact_support_url}/reinstatement\">form</a>",
      instructions: instructions.to_s,
      github_help_url: "<a href=\"#{GitHub.help_url}/articles/github-terms-of-service\">GitHub's Terms of Service</a>",
      tos_violation_review_link: "<a href=\"#{repository.access.tos_violation_review_link}\">Contact GitHub Support</a>",
    }

    mail(
      content_type: "text/html",
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Repository access disabled for #{repository.name_with_display_owner}",
      body: Mustache.render(template, variables),
    )
  end

  def private_information_disabled_notice(repository, instructions = nil, template: nil)
    recipients = user_or_admin_recipients(repository.owner)

    template ||= Stafftools::Repository::DISABLE_TEMPLATE_FOR_PRIVATE_INFORMATION
    variables = {
      repository_name_with_owner: repository.name_with_display_owner,
      contact_url: "<a href=\"#{GitHub.contact_support_url}/reinstatement\">form</a>",
      github_help_url: "<a href=\"#{GitHub.help_url}/articles/github-sensitive-data-removal-policy\">GitHub's Private Information Removal Policy</a>",
      github_appeal_reinstatement_docs_url: "<a href=\"#{GitHub.help_url}/articles/github-appeal-and-reinstatement\">Appeal and Reinstatement Policy</a>",
      instructions: instructions.to_s,
    }

    mail(
      content_type: "text/html",
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Repository access disabled for #{repository.name_with_display_owner}",
      body: Mustache.render(template, variables),
    )
  end

  def trademark_disabled_notice(repository, instructions = nil, template: nil)
    recipients = user_or_admin_recipients(repository.owner)

    template ||= Stafftools::Repository::DISABLE_TEMPLATE_FOR_TRADEMARK
    variables = {
      repository_name_with_owner: repository.name_with_display_owner,
      contact_url: "<a href=\"#{GitHub.contact_support_url}/reinstatement\">form</a>",
      contact_support_url: "<a href=\"#{GitHub.contact_support_url}/contact?subject=TOS+Review&tags=tos-vru\">Contact Support</a>",
      github_help_url: "<a href=\"#{GitHub.help_url}/articles/github-trademark-policy\">GitHub's Trademark Policy</a>",
      github_appeal_reinstatement_docs_url: "<a href=\"#{GitHub.help_url}/articles/github-appeal-and-reinstatement\">Appeal and Reinstatement Policy</a>",
      instructions: instructions.to_s,
    }

    mail(
      content_type: "text/html",
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Repository access disabled for #{repository.name_with_display_owner}",
      body: Mustache.render(template, variables),
    )
  end

  def ssh_deploy_private_key_leaked(repository, url)
    @repository = repository
    @url = url
    recipients = user_or_admin_recipients(repository.owner)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] SSH private deploy key found in commit",
    )
  end

  def ssh_deploy_private_key_leaked_in_gist(repository, url)
    @repository = repository
    @url = url
    recipients = user_or_admin_recipients(repository.owner)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] SSH private deploy key found in Gist",
    )
  end

  def ssh_deploy_private_key_leaked_in_wiki(repository, url)
    @repository = repository
    @url = url
    recipients = user_or_admin_recipients(repository.owner)

    mail(
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] SSH private deploy key found in wiki page",
    )
  end

  def content_warning_notice(repository, category, instructions = nil)
    recipients = user_or_admin_recipients(repository.owner)

    type = TrustSafety::ContentWarnings.type_for(category)

    template ||= \
      if type == "banner"
        Stafftools::Repository::TEMPLATE_FOR_BANNER_CONTENT_WARNING
      else
        Stafftools::Repository::TEMPLATE_FOR_INTERSTITIAL_CONTENT_WARNING
      end
    variables = {
      repository_name_with_owner: repository.name_with_display_owner,
      content_warning_reason: TrustSafety::ContentWarnings.reason_for(category),
      is_student_pages: category == "student_pages",
      instructions: instructions.to_s,
      mis_dis_information_policy_url: "<a href=\"#{GitHub.help_url}/site-policy/acceptable-use-policies/github-misinformation-and-disinformation\">Misinformation and Disinformation Policy</a>",
      appeal_and_reinstatement_url: "<a href=\"#{GitHub.support_url}/contact/reinstatement\">Appeal and Reinstatement</a>",
      github_help_url: "<a href=\"#{GitHub.help_url}/articles/github-acceptable-use-policies\">GitHub's Acceptable Use Policies</a>",
    }

    mail(
      content_type: "text/html",
      from: github,
      to: recipients[:to],
      bcc: recipients[:bcc].concat(bcc_log),
      subject: "[GitHub] Content warning applied to #{repository.name_with_display_owner}",
      body: Mustache.render(template, variables),
    )
  end
end
