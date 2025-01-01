# typed: true
# frozen_string_literal: true

module Notifyd
  # This class exists to render Newsies emails and it is a simpler version of NewsiesMailer.
  #
  # It's a mailer class because Mailers have built in all the rendering system under Rails and it's simpler to use
  # than trying to build a view from scratch.
  # However, we only care about the contents of an email, not the headers or the addresses, that's why this class
  # exists, to reduce the mail construction to just the rendering part, avoiding extra work.
  #
  # NOTE: This is supposed to be temporary. We plan to have a better layout/template system in Notifyd Service
  # that should replace this
  #
  # Example:
  #
  #   message = Newsies::Emails::CheckSuiteEventNotification.new(delivery, settings, options)
  #   mail = Notifyd::BridgeMailer.with(subject: "title", message: message).build_mail
  #   puts mail.html_part.body
  class BridgeMailer < ApplicationMailer
    include UrlHelpers # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
    include UrlHelper # rubocop:todo GitHub/Fanout/RemoveUrlHelpersFromMailers
    # Directory where to look for views relative to app/views.
    self.mailer_name = "mailers/newsies"

    helper :avatar
    helper :url

    def build_mail
      db_pool { build }
    end

    private

    def db_pool(&block)
      return yield if ActiveRecord::Base.single_database_cluster?

      # We miss logic that avoids reading stale data from read replicas, so we fall back to the primary.
      # (see https://github.com/github/notifications/issues/1214)
      ActiveRecord::Base.connected_to(role: :writing) do
        # We are facing an incident related to load on mysql1 (https://github.com/github/github/issues/213382)
        # Data stored in `Mysql1` seems less risky to cause stale notifications
        # or failures in the delivery pipeline, so we temporarily accept reading stale data from `Mysql1`
        # to avoid global outages across the whole site.

        # rubocop:todo GitHub/OnlyCallConnectedToOnActiveRecordBase
        ApplicationRecord::Mysql1.connected_to(role: :reading, &block)
        # rubocop:enable GitHub/OnlyCallConnectedToOnActiveRecordBase
      end
    end

    def build
      @subject          = params[:subject]
      @message          = params[:message]
      @try_local_assets = params[:try_local_assets]

      @comment = @message.comment

      email = mail(subject: @subject) do |format|
        @message.parts.each do |type, body|
          format.custom(Mime::Type.lookup(type)) do
            case body
            when String
              render plain: body.scrub
            when Symbol
              if @message.primer_html_template_enabled?
                render template: "newsies/#{body}", layout: "layouts/#{@message.primer_layout}"
              else
                render template: "newsies/#{body}"
              end
            else
              fail "invalid body: #{body.inspect}"
            end
          end
        end
      end

      premailer_options = { adapter: :nokogiri_fast }

      if @try_local_assets
        # this generates a local file:// URI if the assets exist on disk
        premailer_options[:css] = MailerBundleHelper.primer_email_stylesheet_uris
        # this makes it so premailer doesn't try to download linked link and
        # style targest in the layout
        premailer_options[:include_link_tags] = false
        premailer_options[:include_style_tags] = false
      end

      convert_to_premail(email, premailer_options: premailer_options) if @message.primer_html_template_enabled?

      email
    end
  end
end
