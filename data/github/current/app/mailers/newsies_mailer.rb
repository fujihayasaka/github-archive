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
            GitHub.dogstats.distribution_time("newsies", tags: ["action:notification", "type:string"]) do
              render plain: body.scrub
            end
          when Symbol
            GitHub.dogstats.distribution_time("newsies", tags: ["action:notification", "type:symbol"]) do
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
end
