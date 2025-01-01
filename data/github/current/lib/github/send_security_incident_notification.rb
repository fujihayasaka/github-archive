# typed: false
# frozen_string_literal: true

module GitHub
  # Class for sending security incident notifications to a set of users by user id.
  class SendSecurityIncidentNotification

    attr_reader :dry_run, :verbose

    BATCH_SIZE = 100

    def initialize(subject:, template:, from:, dry_run: false, verbose: false, **_)
      @subject = subject
      @template = template
      @from = from
      @dry_run = dry_run
      @verbose = verbose
    end

    # Public: Send notifications.
    #
    # data - Array of hashes with each hash containing key `:user_id` and integer value and
    #        possibly other keys and values to pass to the email template.
    def perform(data)
      log "Starting #{self.class.to_s.underscore}"
      count = 0

      data.each_slice(BATCH_SIZE) do |batch|
        # get the users for this batch and group them by user id
        users = User.where(id: batch.map { |item| item[:user_id] }).group_by { |user| user.id.to_s }

        # create a new array that will get reset on each new batch
        enriched_batch = []

        # iterate through the batch
        batch.each do |item|
          # get the user for this batch item
          user = users[item[:user_id]].try(:first)

          # if no user was found skip this batch item
          if user.nil?
            log "Skipping user (#{item[:user_id]}) that could not be found" if verbose
            next
          end

          # clone the batch item so that we can add the user to it without modifying the original
          # data item, preventing memory bloat
          item = item.clone

          # add the user and user login to new item
          item[:user] = user
          item[:login] = user.login

          # add the item to the enriched batch
          enriched_batch << item
        end

        # iterate over the enriched batch and send email notifications
        enriched_batch.each do |item|
          log "Processing #{item[:user]} (#{item[:user_id]})" if verbose

          user = item[:user]
          send_email(user, item.except(:user))

          count += 1
          log("Processed #{count}") if count % BATCH_SIZE == 0
        end
      end

      log "Finished #{self.class.to_s.underscore}, processed #{count} records."
    end

    def perform_for_user(user, data)
      send_email(user, data)
    end

    private

    SMTP_SERVER_ERRORS = [
      IOError,
      Net::SMTPAuthenticationError,
      Net::SMTPServerBusy,
      Net::SMTPUnknownError,
      Errno::ECONNREFUSED,
    ]

    SMTP_CLIENT_ERRORS = [
      Net::SMTPFatalError,
      Net::SMTPSyntaxError,
    ]

    SMTP_ERRORS = SMTP_SERVER_ERRORS.concat(SMTP_CLIENT_ERRORS)

    def send_email(user, options)
      mail = SecurityMailer.incident_notification(options.merge({
        user: user,
        from: @from,
        subject: @subject,
        body: render_template(options),
      }))

      if dry_run
        if verbose
          preview_parts = [
            "Email preview:",
            "From: #{mail.from.first}",
            "To: #{mail.to.inspect}",
            "Subject: #{mail.subject}",
            mail.body.to_s,
            "",
          ]
          log preview_parts.join("\n")
        end

        return
      end

      begin
        mail.deliver_now!
        log "Sent email to #{options[:user]} (#{options[:user].id})" if verbose
      rescue *SMTP_ERRORS => error
        log "Error email to #{options[:user]} (#{options[:user].id}): #{error}"
      end
    end

    def render_template(options)
      Mustache.render(@template, fix_newlines(options))
    end

    def fix_newlines(options)
      new_options = {}

      options.each do |key, value|
        if value.is_a?(String)
          new_options[key] = value.gsub("\\n", "\n")
        else
          new_options[key] = value
        end
      end

      new_options
    end

    # Private: Write a log message - send to STDOUT if not in test
    def log(message)
      m = dry_run ? "Dry run: #{message}" : message
      Rails.logger.debug m
      return if Rails.env.test?
      puts "[#{Time.now.iso8601.sub(/\A-\d+:\d+\z/, '')}] #{m}"
    end
  end
end
