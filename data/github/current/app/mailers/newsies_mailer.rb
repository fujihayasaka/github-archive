# typed: true
# frozen_string_literal: true

class NewsiesMailer < ApplicationMailer
  include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
  MULTI_HEADERS = ["Received"]

  # Directory where to look for views relative to app/views.
  self.mailer_name = "mailers/newsies"

  helper :avatar
  helper :url

  # Public: Deliver notification to a user.
  #
  # Note: some special headers like 'Received' must be specified as separate
  # header lines. The mail headers object supports this but you have to set
  # the same key multiple times. Array assignment is not supported. These
  # headers should be marked in the MULTI_HEADERS array.
  #
  # message - An instance of Newsies::Emails::Message
  #
  # Returns nothing
  def notification(message)
    message.headers.each do |k, v|
      if MULTI_HEADERS.include?(k)
        Array(v).each { |line| headers[k] = line }
      else
        headers[k] = v
      end
    end

    opts = {
      to:           message.to,
      from:         message.from,
      reply_to:     message.reply_to,
      cc:           message.cc_list,
      bcc:          message.bcc,
      subject:      message.subject,
      destinations: message.destinations,
    }

    is_mail_rendered_with_primer_template = T.let(false, T::Boolean)
    mail = mail(opts) do |format|
      message.parts.each do |type, body|
        format.custom(Mime::Type.lookup(type)) do
          case body
          when String
            GitHub.dogstats.time("newsies", tags: ["action:notficiation", "type:string"]) do
              render plain: body.scrub
            end
          when Symbol
            GitHub.dogstats.time("newsies", tags: ["action:notficiation", "type:symbol"]) do
              @message = message
              @comment = message.comment
              if message.primer_html_template_enabled?
                is_mail_rendered_with_primer_template = true
                render template: "newsies/#{body}", layout: "layouts/#{@message.primer_layout}"
              else
                render template: "newsies/#{body}"
              end
            end
          else
            fail "invalid body: #{body.inspect}"
          end
        end
      end
    end

    if is_mail_rendered_with_primer_template
      # Primer template emails must be sent using Premailer to inline CSS
      convert_to_premail(mail)
    else
      mail
    end
  end

  # Public: Deliver notice about being automatically subscribed to
  # notifications for one or more repositories.
  #
  # user                  - User who will be receiving the email
  # email_address         - A String email address
  # repositories          - An Array of Repository instances
  #
  # Returns nothing
  def auto_subscribe(user, email_address, repositories)
    return if repositories.empty?
    if repository = mention_repository?(repositories)
      context = { repository: repository }

      if user.present?
        token = GitHub.newsies.token(:unsubscribe, user, repository.id)
        context[:unsubscribe_link_token] = token
      end

      @unsubscribe_link_token = context[:unsubscribe_link_token]

      subject = "[GitHub] Subscribed to #{repository.name_with_display_owner} notifications"
      template = "auto_subscribe"
      @repository = repository
    elsif owner = mention_common_owner?(repositories)
      subject = "[GitHub] Subscribed to #{repositories.size} #{owner.display_login} repositories"
      template = "auto_subscribe_many"
      @repositories = repositories
    else
      subject = "[GitHub] Subscribed to #{repositories.size} repositories"
      template = "auto_subscribe_many"
      @repositories = repositories
    end

    mail(
      to: email_address,
      subject: subject,
      template_name: template,
    )
  end

  def mention_repository?(repositories)
    repositories.size == 1 && repositories.first
  end

  def mention_common_owner?(repositories)
    owners = repositories.map { |r| r.owner_id }
    owners.uniq!
    owners.size == 1 && repositories.first.owner
  end
end
