# typed: false
# frozen_string_literal: true

module GitHub
  # This module does very basic spam checking.
  module SpamChecker
    include Scientist

    extend self

    # Historically we have waited 10 seconds to give async spam checks time to finish https://github.com/github/notifications/issues/296
    # Platform Health has requested to temporarily up this limit as we combat a massive abuse campaign https://github.slack.com/archives/C04553EJWE4/p1709334185781959
    DELAY_FOR_EXTERNAL_CHECKS = 20.seconds
    HARD_SPAM_FLAG_PHRASE = "[octocat approved]"
    HARD_SPAM_FLAG_REGEXP = /#{Regexp.escape(HARD_SPAM_FLAG_PHRASE)}/

    # Are external spamminess checks enabled, i.e. should we add the DELAY_FOR_EXTERNAL_CHECKS
    # These are only enabled in production on dotcom
    def external_spamminess_check_enabled?
      GitHub::AppEnvironment.production? &&
        GitHub.spamminess_check_enabled? &&
        !GitHub.dynamic_lab? &&
        !GitHub.staff_host?
    end

    def add_to_message_with_limit(message, addition, total_length = 255)
      addition_length = addition.length + 2
      [message[0..(total_length - addition_length)], addition].join(" ")
    end

    # Does the reason for flagging indicate a hard flag?
    #
    # reason - String
    #
    # Returns Boolean
    def is_hard_flag?(reason)
      reason =~ HARD_SPAM_FLAG_REGEXP
    end

    def make_hard_reason(reason)
      add_to_message_with_limit(reason,
                                GitHub::SpamChecker::HARD_SPAM_FLAG_PHRASE, 255)
    end

    # Send this msg to The Spam Notifications Room
    def notify(message)
      return unless GitHub.spamminess_check_enabled?

      if GitHub::AppEnvironment.development? || GitHub::AppEnvironment.test?
        Rails.logger.info("Chat - Spam Notifications: #{message}")
      else
        Spam.notify(message: message)
      end
    end

    def activity_count(user)
      {
        followers: user.followers.count,
        following: user.following.count,
        gists: user.gists.count,
        gist_comments: user.gist_comments.count,
        issues: user.issues.without_pull_requests.count,
        issue_comments: user.issue_comments.count,
        pull_requests: user.pull_requests.count,
        repos: user.repositories.not_forks.count,
        commit_comments: user.commit_comments.count,
        wiki_edits: wiki_edit_count,
        stars: user.starred_repositories_count,
      }
    end

    def wiki_edit_count
      if user.feature_enabled?(:conduit_wiki_edits)
        wiki_edit_items(user).size
      else
        wiki_edits(user).count
      end
    end

    def wiki_edits(user)
      return [] unless user.is_a?(User) || (user = User.find_by_login(user))

      if user.feature_enabled?(:conduit_wiki_edits)
        Conduit::Api::Feed.new(user, viewer: user, twirp_items: wiki_edit_items(user)).build.items
      else
        event_selector = "actor:#{user.id}:public"
        events = Stratocaster::Timeline.new(event_selector).events
        events.select { |t| t.event_type == Stratocaster::Event::GOLLUM_EVENT }.select { |t| wiki_edit?(t) }
      end
    end

    def wiki_edit?(event)
      return false unless event.respond_to? :payload
      payload = event.payload

      payload["pages"].present? &&
        %w[edited created].include?(payload["pages"][0]["action"])
    end

    # Returns true for some moderately arbitrary combinations of activity.
    #
    # For instance, when dealing with Users, we don't count the number of
    # Gists or GistComments at all, because spammers do zillions of them.
    # But at the moment spammers aren't often meeting these particular criteria.
    #
    # This is quite gamable, but for the moment it's a useful signal to
    # avoid flagging active users as fake or automated spam accounts.
    #
    # account - User, Organization, or Business
    #
    # Returns Boolean.
    def fairly_active?(account)
      # All the current checks don't apply to Businesses
      return false if account.is_a?(Business)

      # Recently created hyperactive accounts don't qualify
      return false unless account.created_at < 24.hours.ago

      num_followers = account.followers.limit(9).count
      num_issues = account.issues.without_pull_requests.limit(7).count # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      num_issue_comments = account.issue_comments.limit(7).count
      num_repos = account.repositories.where(parent_id: nil).limit(7).count
      num_commit_comments = account.commit_comments.limit(5).count

      result   = account.has_app_enabled?
      result ||= num_repos > 2 && (num_followers + num_issues + num_commit_comments) > 4
      result ||= (num_repos > 3 || num_followers > 8)
      result ||= (num_issue_comments + num_commit_comments) > 4
      result ||= (num_issues + num_issue_comments + num_repos) > 6
      result
    end

    # Is the account "old", hammy, has paid money, or fairly active?
    #
    # account - User, Organization, or Business
    #
    # Returns Boolean
    def old_or_active?(account)
      account.created_at < 30.days.ago || account.hammy? || has_account_paid_money?(account) || fairly_active?(account)
    end

    # Public: Has this account actually paid money to GitHub at some point?
    #
    # account - A User, Organization, Bot, or Business.
    #
    # Bot accounts return false.
    # Invoice accounts return true.
    # All other accounts are checked for a successful BillingTransaction.
    #   Successful is defined as  :submitted_for_settlement, :settling or :settled
    #
    # Returns a boolean.
    def has_actually_paid_money?(account)
      return false if account.respond_to?(:type) && account.type == "Bot"

      # The account is high value and doesn't pay through the normal billing setup.
      return true if account.invoiced?

      # A chargeback or authorization should not be counted as a successful
      # transaction for our purposes here.
      #
      # Presumably, successful statuses could change over time. By including
      # all success statuses by default (and removing just the one we care
      # about), we're erring on the side of giving accounts the benefit of
      # the doubt. Given that this field may be used to determine if an
      # account should be spamflagged, erring in this direction seems
      # preferable to adding false positives.
      successful_statuses = ::Billing::BillingTransactionStatuses::SUCCESS
        .except(:charged_back)
        .except(:authorization_cancelled)
        .values

      customer_id = account.is_a?(Business) && account.customer_id.presence || 0

      if account.feature_enabled?(:billing_transactions_query_fix)
        sql = Arel.sql(<<-SQL)
          SELECT sale.id
          FROM billing_transactions AS sale
          LEFT JOIN billing_transactions AS refund
          ON sale.transaction_id = refund.sale_transaction_id
          WHERE
        SQL

        if account.is_a?(Business)
          sql += Arel.sql(<<-SQL, customer_id: customer_id)
            sale.customer_id = :customer_id
          SQL
        else
          sql += Arel.sql(<<-SQL, user_id: account.id)
            sale.user_id = :user_id
          SQL
        end

        sql += Arel.sql(<<-SQL, successful_statuses: successful_statuses)
          AND refund.id IS NULL
          AND sale.amount_in_cents > 0
          AND sale.transaction_type != 'refund'
          AND sale.last_status IN (:successful_statuses)
          LIMIT 1
        SQL

        rows = ::Billing::BillingTransaction.connection.select_rows(sql)
        rows.present?
      else
        rows = ::Billing::BillingTransaction.connection.select_rows(Arel.sql(<<-SQL, user_id: account.id, customer_id: customer_id, successful_statuses: successful_statuses))
          SELECT sale.id
          FROM billing_transactions AS sale
          LEFT JOIN billing_transactions AS refund
          ON sale.transaction_id = refund.sale_transaction_id
          WHERE (sale.user_id = :user_id OR sale.customer_id = :customer_id)
          AND refund.id IS NULL
          AND sale.amount_in_cents > 0
          AND sale.transaction_type != 'refund'
          AND sale.last_status IN (:successful_statuses)
          LIMIT 1
        SQL

        rows.present?
      end
    end

    # Public: Has this account, or its orgs, actually paid money to GitHub at some point?
    #
    # account - A User, Organization, or Business.
    #
    # Returns a boolean.
    def has_account_paid_money?(account)
      return true if has_actually_paid_money?(account)

      account.organizations.first(10).any?(&method(:has_actually_paid_money?))
    end

    # Public: We want to verify that they have paid money twice:
    #  $ once in the "current billing cycle" (read: past 30 days plus a three day buffer)
    #  $ once in the "previous billing cycle" (read: previous 30 days plus a three day buffer)
    #
    # account - An account.
    #
    # returns a boolean
    def has_consecutive_billing_success?(account)
      return false if account.respond_to?(:type) && account.type == "Bot"

      # The account is high value and doesn't pay through the normal billing setup.
      return true if account.invoiced?

      # yearly billing means that they have paid a lot and not within the last 30 days
      return true if account.plan_duration == User::BillingDependency::YEARLY_PLAN

      # get settled transactions for the current billing period (i.e. created_at after 33.days.ago)
      current_billing_period_check = billing_success_in_period(account, 33.days.ago, Time.now)

      # get out fast so we don't have to check the previous billing period
      return false unless current_billing_period_check

      # get settled transactions for the previous billing period (i.e. created_at after 66.days.ago but before 33.days.ago)
      previous_billing_period_check = billing_success_in_period(account, 66.days.ago, 33.days.ago)

      (current_billing_period_check && previous_billing_period_check)
    end

    # Public: This method finds transactions that fit this criteria:
    #   * must be "successful" (currently :submitted_for_settlement, :settling, or :settled - NOT :charged_back)
    #   * not refunded
    #   * greater than zero cents
    #   * between start_date and end_date
    #
    # Bot accounts return false.
    # Invoice accounts return true.
    #
    # account - A User, Organization, or Business.
    # start_date - A Time object
    # end_date - A Time object
    #
    # @return [Boolean]
    def billing_success_in_period(account, start_date = 1.month.ago, end_date = Time.now)
      return false unless account.present?

      if account.feature_enabled?(:org_upgraded_trust_tiers_v2)
        return false if account.respond_to?(:type) && account.type == "Bot"

        # The account is high value and doesn't pay through the normal billing setup.
        return true if account.invoiced?
      end

      successful_statuses = ::Billing::BillingTransactionStatuses::SUCCESS
        .except(:charged_back)
        .except(:authorization_cancelled)
        .values

      customer_id = account.is_a?(Business) && account.customer_id.presence || 0

      if account.feature_enabled?(:billing_transactions_query_fix)
        sql = Arel.sql(<<-SQL)
          SELECT sale.id
          FROM billing_transactions AS sale
          LEFT JOIN billing_transactions AS refund
          ON sale.transaction_id = refund.sale_transaction_id
          WHERE
        SQL

        if account.is_a?(Business)
          sql += Arel.sql(<<-SQL, customer_id: customer_id)
            sale.customer_id = :customer_id
          SQL
        else
          sql += Arel.sql(<<-SQL, user_id: account.id)
            sale.user_id = :user_id
          SQL
        end

        sql += Arel.sql(<<-SQL, successful_statuses: successful_statuses, start_date: start_date, end_date: end_date)
          AND sale.created_at BETWEEN :start_date AND :end_date
          AND refund.id IS NULL
          AND sale.amount_in_cents > 0
          AND sale.transaction_type != 'refund'
          AND sale.last_status IN (:successful_statuses)
          LIMIT 1
        SQL

        rows = ::Billing::BillingTransaction.connection.select_rows(sql)
        rows.present?
      else
        rows = ::Billing::BillingTransaction.connection.select_rows(Arel.sql(<<-SQL, account_id: account.id, customer_id: customer_id, successful_statuses: successful_statuses, start_date: start_date, end_date: end_date))
          SELECT sale.id
          FROM billing_transactions AS sale
          LEFT JOIN billing_transactions AS refund
          ON sale.transaction_id = refund.sale_transaction_id
          WHERE (sale.user_id = :account_id OR sale.customer_id = :customer_id)
          AND sale.created_at BETWEEN :start_date AND :end_date
          AND refund.id IS NULL
          AND sale.amount_in_cents > 0
          AND sale.transaction_type != 'refund'
          AND sale.last_status IN (:successful_statuses)
          LIMIT 1
        SQL

        rows.present?
      end
    end

    GIST_MAX_FILE_DATA = 100 * 1024
    MAX_BLOB_SIZE_TO_CHECK = 50 * 1024

    # Spammers like to post a mostly innocuous Gist, and then followup
    # with tons of spammy comments on their own Gist.
    def test_gist_owner_comments(gist)
      gist.comments.select { |gc| gc.user_id == gist.user_id }.detect { |gc| GitHub::SpamChecker.check_text(gc.body) }
    end

    PATH_EXTS_TO_SKIP = %w[ .apk .bin .css .db .dex .gif .gz .ico .iml .ipynb
                            .jar .java .jpg .mov .mp3 .ogg .pdf .png .psd
                            .sql .svg .swf .tgz .zip
                          ]

    # Verbose mode is for console use.
    def get_repo_filenames(repo, verbose = false)
      oid = repo.default_oid

      # Can't do much if the default oid is nil
      if oid.nil?
        puts "Master sha is nil for #{repo.name}. Skipping it." if verbose
        return []
      end

      # Skip files we don't care about or can't check anyway
      repo.tree_file_list(oid).reject { |f| f.end_with?(*PATH_EXTS_TO_SKIP) }
    end

    def quick_check_pages_repo(repo, verbose = false)
      if repo.owner.spammy?
        puts "Already spammy owner #{repo.name} #{repo.owner.login}: #{repo.owner.spammy_reason}" if verbose
        return 100
      end

      spam_score = 0
      report = +""

      gnarly_filenames = get_repo_filenames(repo, verbose)
      filenames = gnarly_filenames.map { |f| cleanup_text(f) }
      clean_to_gnarly = Hash[filenames.zip(gnarly_filenames)]

      # Again with the tasty console-use juice
      if verbose.is_a?(Integer) && verbose.to_i > 1
        puts "Checking #{filenames.count} filenames"
      end

      # ton of filenames? Almost all on one dir level? Spammer.
      file_count = filenames.count
      deep_count = filenames.count { |f| f =~ /\// }
      shallow_count = file_count - deep_count
      if (file_count > 100 && deep_count < 3) ||
         (file_count > 500 && deep_count < (0.01 * file_count))
        report << "SPAM! #{repo.name} by #{repo.owner.login} has #{file_count - deep_count} top-level files (out of #{file_count} total)"
        spam_score += 30
      end

      if (file_count > 2000) && deep_count < (0.01 * file_count)
        spam_score += 10
        return spam_score
      end

      js_files = filenames.select { |f| f =~ /\.js\z/i }

      js_regexp = GitHub::SpamChecker::NAUGHTY_JS

      pages_pattern = nil
      # Is he using the naughty JS to track his Google power? Spammer.
      naughty_file = js_files.find do |f|
        begin
          blob = repo.tree_entry(repo.default_oid, clean_to_gnarly[f], limit: MAX_BLOB_SIZE_TO_CHECK)
          next unless blob

          naughty = js_regexp.any? do |expr|
            expr.all? { |e| blob.data =~ e }
          end

          naughty ||= Spam.get_current_patterns("pages_js").any? do |expr|
            if blob.data =~ Regexp.new(expr)
              pages_pattern = expr
              true
            end
          end
        rescue GitRPC::Failure
          next
        end
      end

      if naughty_file
        report << " and a spammy .js file: #{naughty_file}"
        report << " . Matched pattern: #{pages_pattern}"
        spam_score += 40
      end

      # Don't do the HTML checks if there are not at least 3 files in the repo,
      # or if the number of top-level files are less than 65% of the total file
      # count. Spammers put most of their files at the top level, and this
      # avoids walking through some *large* legitimate repos.
      if (file_count > 2) && shallow_count > (0.65 * file_count)
        html_files = filenames.select { |f| f =~ /\.html?\z/i }
        html_file_count = html_files.count

        text_naughty_count = 0

        naughty_html_files = html_files.select do |f|
          next unless blob = repo.blob(repo.default_oid, clean_to_gnarly[f])
          next if blob.data.nil?  # Usually means file was too large to retrieve

          text_says_spam  = check_text blob.data

          text_naughty_count += 1 if text_says_spam

          text_says_spam
        end

        if html_file_count > 0
          text_naughty_ratio = (100.0 * text_naughty_count) / html_file_count
          if text_naughty_ratio >= 75.0
            report << " and %.01f%% (%d) of its %d HTML files look spammy" % [text_naughty_ratio, text_naughty_count, html_file_count]
            spam_score += 20
          end
        end
      end

      if spam_score < 25  # Arbitrary numbers FTW! TODO: Probably just == 0
        report << "NO NO NO! #{repo.name} by #{repo.owner.login} is INNOCENT, I tell you."
      end

      puts report if verbose
      spam_score
    end

    # Check a repo to see if it smells like spam
    #
    # repo - the Repository to test
    #
    # Returns a String containing a reason if the repo is spammy, nil otherwise
    def test_repo(repo)
      # Forkers aren't spammy, at least not yet
      return if repo.fork? || repo.private?

      reasons = []

      if repo.is_user_pages_repo?
        if quick_check_pages_repo(repo) > 35
          reasons << "Pages branch"
        end
      end

      # Test the text fields against the blocklist
      reasons << "Description" if spammy_text(repo.description).present?
      reasons << "Homepage" if check_text(repo.homepage)
      reasons << "Name" if spammy_text(repo.name).present?
      if reasons.present?
        "Repo spam (id: #{repo.id} -> #{repo.permalink}) : #{reasons.join(', ')}"
      end
    end

    # Returns a spamminess score from 0.0 (pure as the new-fallen snow) to
    # 1.0 (wickedest filth ever conceived).
    def score_repo_content(repo, verbose = false)
      return 1.0 if repo.owner.spammy?
      return 0.0 if repo.empty?

      if verbose
        puts "Checking repo #{repo.name} (#{repo.id}), belonging to #{repo.owner.login} (#{repo.owner.id})"
      end

      all_filenames = get_repo_filenames(repo, verbose)
      possible_offenders = []

      all_filenames.each do |filename|
        blob = repo.tree_entry(repo.default_oid, filename, limit: MAX_BLOB_SIZE_TO_CHECK)
        next unless blob

        if GitHub::SpamChecker.check_text(blob.data)
          possible_offenders << filename
          if verbose
            puts "\t" + "X" * 50
            naughty = GitHub::SpamChecker.spammy_text(blob.data)
            puts "FOUND ONE by #{repo.owner.login}: #{filename}\n\t#{naughty}"
            puts "\t" + "X" * 50
          end
        end
      end

      percent = 100.0 * possible_offenders.size / all_filenames.size
      if all_filenames.size > 4 && percent > 50.0
        if verbose
          puts "#{repo.name} is HIGHLY LIKELY SPAM (%.02f %%)" % percent
        end
        # We're pretty sure at this point, so give a high score
        [percent, 0.9].max
      elsif percent > 0.1
        if all_filenames.size > 4
          # if we found something, and there were enough files to check
          # return the percent we found.
          percent
        else
          # otherwise, return a fairly low, but non-zero, score
          0.1
        end
      else
        # Looks OK from what we know how to check right now.
        0.0
      end
    end

    # Public: Check whether a Business appears to be spammy.
    #
    # Checks whether any of the member organizations appear to be spammy
    # using existing rules for evaluating Users/Organizations.
    #
    # business - The Business to test.
    #
    # Returns String.
    def test_business(business)
      reasons = []
      if business && business.organizations.any?
        business.organizations.each do |org|
          reasons << test_user_login(org)
        end
      end
      reasons.compact!

      if reasons.present?
        "Enterprise account member org spam (#{reasons.join(', ')})"
      end
    end

    # Check a User to see if he smells like a spammer
    #
    # user - the user to test
    #
    # Returns a String containing a reason if the user is spammy, nil otherwise
    def test_user(user)
      reasons = []

      reasons << test_user_login(user)

      reasons.compact!

      if reasons.present?
        "User account spam (#{reasons.join(', ')})"
      end
    end

    def get_email_parts(email)
      email = email.email if email.is_a? User

      return [] if email.nil?

      mailbox, domain = email.split("@")

      mailbox.strip! if mailbox
      domain.strip! if domain
      [mailbox, domain]
    end

    # TODO: Only thing left to port here is Spam.login_is_tainted?
    # as of 2019-12-09
    def test_user_login(user)
      return if user.nil?

      if last_id = Spam.login_is_tainted?(user.login)
        audit_link = "https://github.com/stafftools/audit_log?query=%28user_id%3A#{last_id}+OR+actor_id%3A#{last_id}%29"
        notify ":postal_horn: Flagging #{user.login} as tainted; previous User id: #{last_id} (#{audit_link})"
        return "login was on tainted list; previous User id: #{last_id}"
      end

      # If we got to here, all clear
      nil
    end

    # Check the content for a wiki and return a reason for its spamminess,
    # if it is.
    def test_wiki_content(content)
      if content =~ /(support (?:phone )?number[\s,].+){3,}/im ||
         content =~ /(technical support[\s,].+){3,}/im
        "Tech Support Wiki spam"
      elsif content =~ /solahart/im
        "Solahart Wiki spam"
      else
        Spam.get_current_patterns("wiki").each do |expr|
          if content =~ Regexp.new(expr)
            return "Content matched Wiki pattern #{expr}"
          end
        end
        # If nothing else matched, do regular content check
        if GitHub::SpamChecker.check_text(content)
          return "Content matched general spam pattern"
        end

        false
      end
    end

    # Flag a User who is attempting to put spam into a wiki.
    def flag_wiki_updater(page, user, repo, reason)
      if reason == "Tech Support Wiki spam"
        GlobalInstrumenter.instrument(
          "add_account_to_spamurai_queue",
          {
            account_global_relay_id: user.global_relay_id,
            additional_context: "SpamChecker#flag_wiki_updater - #{reason}",
            origin: :RESQUE_WIKI_PAGE_SPAM_CHECK,
            queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
          },
        )
        user.safer_mark_as_spammy(reason: "#{reason} on #{repo.permalink}/wiki/#{page.to_param}")
        notify(":hammer:ed User '#{user.login}' for #{reason} on #{repo.permalink}/wiki/#{page.to_param}")
      elsif reason == "Solahart Wiki spam"
        user.safer_mark_as_spammy(reason: "#{reason} on #{repo.permalink}/wiki/#{page.to_param}")
        notify(":hammer:ed User '#{user.login}' for #{reason} on #{repo.permalink}/wiki/#{page.to_param}")
      elsif reason =~ /Content matched Wiki pattern/i
        user.safer_mark_as_spammy(reason: "#{reason} on #{repo.permalink}/wiki/#{page.to_param}")
        notify(":hammer:ed User '#{user.login}' because #{reason} on #{repo.permalink}/wiki/#{page.to_param}")
      elsif reason
        GlobalInstrumenter.instrument(
          "add_account_to_spamurai_queue",
          {
            account_global_relay_id: user.global_relay_id,
            additional_context: "SpamChecker#flag_wiki_updater - default",
            origin: :RESQUE_WIKI_PAGE_SPAM_CHECK,
            queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
          },
        )
        notify("User '#{user.login}' is guilty of WIKI SPAM on #{repo.permalink}/wiki/#{page.to_param}: #{reason}")
      end
    end

    def test_wiki_page(page, user, repo)
      if reason = test_wiki_content(page.data_html.to_s)
        flag_wiki_updater page, user, repo, reason
        true
      end
    end

    #########################################################################
    #########################################################################
    ## From here to the end has been ported to Hamzo.
    ## CAUTION: DO NOT ADD ANYTHING BELOW HERE WITHOUT ALSO ADDING TO HAMZO.
    #########################################################################
    #########################################################################

    # Maximum number of links to the same URL in a single unit of content
    # before we get suspicious.
    DUPLICATE_LINK_THRESHOLD = 6

    # Check a comment (Gist, Commit, Issue, PullRequestReview, etc) to see if
    # it's spammy.
    #
    # comment - the Comment to test
    #
    # Returns the String reason if the Comment is spammy, or nil otherwise.
    def test_comment(comment)
      return nil unless user = comment.user   # how is this User nil?

      # This method is used by some active filtering, so let's bail out early
      # if the user is already spammy or allowlisted.
      return user.spammy_reason if user.spammy?
      return nil unless user.can_be_flagged?

      # We have both GistComments and IssueComments with nil bodies in the DB.
      return nil if comment.body.nil?

      # Don't flag a user for comments on a repo to which he has rights.
      if repo = comment.try(:repository)
        return nil if repo.private? && repo.member?(user)
      end

      reasons = []
      comment_id_str = comment.id.to_s

      specimen = Spam::Specimen.new(comment.body)
      just_text = cleanup_text(specimen.text)

      # Check the body contents for naughtiness
      reasons << "content" if check_text(just_text)

      if specimen.has_repeated_links?(DUPLICATE_LINK_THRESHOLD)
        reasons << "comment has too many links to the same URL #{DUPLICATE_LINK_THRESHOLD}"
      end

      if reasons.present?
        "#{comment.class} spam (id #{comment.id}): #{reasons.join(', ')}"
      else
        nil    # Yeah, I know the expression is nil anyway, but clarity ftw.
      end
    end

    def check_content_path_and_description(content, path, description)
      content = cleanup_text(content)
      path = cleanup_text(path)
      description = cleanup_text(description)

      # Avoid false positives on things like "hello, world" and "test"
      if content.length > 20
        if path.length > 20 && content[0..path.length - 1] == path
          return "single path name (#{summarize_gist_path(path)}) was same as data"
        end

        if (description.present? &&
             description.length > 20 &&
             content[0..description.length - 1] == description
           )
          "description (#{description}) was same as data"
        end
      end
    end

    GIST_MAX_PATH_LENGTH = 300
    def summarize_gist_path(path)
      filename = path[0..GIST_MAX_PATH_LENGTH]
      if path.length > GIST_MAX_PATH_LENGTH
        filename += "." * 3
      end
      filename
    end

    # Check a User Profile to see if he smells like spam
    #
    # profile - the Profile to test
    #
    # Returns a String containing a reason if the profile is spammy, nil otherwise
    def test_profile(profile)
      # Nothing to test if the profile is missing
      return if profile.nil?

      reasons = []

      # Test the text fields against the blocklist
      reasons << "Profile blog spam" if spammy_text(profile.blog).present?
      reasons << "Profile name spam" if check_text(profile.name)
      reasons << "Profile company spam" if check_text(profile.company)
      reasons << "Profile location spam" if check_text(profile.location)

      if reasons.present?
        "Profile spam (#{reasons.join(', ')})"
      end
    end

    #    MIN_DOT_COUNT = 3
    MIN_DUPE_COUNT = 3
    #    LONG_MAILBOX_SIZE = 12

    # Test a User's email attribute (in practice, only one of the UserEmails
    # which might be associated with an account) for spamminess.
    #
    # Returns a String with the reasons we think it's spammy (if we do) or nil
    # (if we don't).

    def count_obfuscated_duplicate_emails(user, options = nil)
      return 0 if !GitHub.flipper[:include_emu_users].enabled? && user.is_enterprise_managed?

      options ||= {}
      pattern = UserEmail.deobfuscate user.email
      base = options[:skip_spammy] ? UserEmail.not_spammy : UserEmail
      if !GitHub.flipper[:include_emu_users].enabled?
        base = base.not_enterprise_managed
      end
      scope = base.where(deobfuscated_email: pattern).where("user_id <> ?", user.id)
      ActiveRecord::Base.connected_to(role: :reading) do
        scope.count
      end
    end

    def find_obfuscated_duplicate_emails(user, options = nil)
      return [] unless user.email.present?
      return [] if !GitHub.flipper[:include_emu_users].enabled? && user.is_enterprise_managed?

      options ||= {}
      limit = (options[:limit] || 100).to_i  # Let's don't get crazy
      pattern = UserEmail.deobfuscate user.email
      base = options[:skip_spammy] ? UserEmail.not_spammy : UserEmail
      if !GitHub.flipper[:include_emu_users].enabled?
        base = base.not_enterprise_managed
      end
      scope = base.where(deobfuscated_email: pattern).where("user_id <> ?", user.id).limit(limit)
      ActiveRecord::Base.connected_to(role: :reading) do
        scope.to_a
      end
    end

    #########################################################################
    # Everything past this point is in Hamzo, in app/lib/pattern_helpers.rb
    #########################################################################

    WORD_BLOCKLIST = [
      /BangBus/i, /Megavideo/i, /getsexon/i, /locksmith/i, /lolita/i, /preteen/i,
      /solahart/i, /(order|buy)\s+(\w+)?\s*online/i, /Download eBook/i,
      /click link above/i, /Streaming Online Video/i, /watch streaming online/i,
      /payday loan/i, /milf(?!o)/i,
    ]

    # Constructs a blocklist regexp that will match any of the given words or
    # regexps, ignoring case. Regexp#union doesn't accept flags, so we have to
    # pass its source into Regexp#new with the flags.
    BLOCKLIST_REGEXP = Regexp.new(Regexp.union(*WORD_BLOCKLIST).source, Regexp::IGNORECASE)

    # Test if a given string contains any blocklisted words.
    #
    # text - String to test
    #
    # Returns Boolean indicating if the String matches the blocklist regexp.
    def blocklisted?(text)
      text =~ BLOCKLIST_REGEXP
    end

    # Show what entries in word_list match in the given text.  We do this
    # word-by-word (instead of using BLOCKLIST_REGEXP, above) so that we
    # can get a list of the individual elements that matched. Only used
    # in spam_checker_test.rb.
    #
    # word_list = Array of words or regexen
    # text      = String to test
    #
    # Returns an Array of all the word_list entries that cause a match.
    def get_matching_words(word_list, text)
      matching_words = []
      word_list.each do |word|
        rexp = Regexp.new(Regexp.union(word).source, Regexp::IGNORECASE)
        matching_words << word if text =~ rexp
      end
      matching_words
    end

    def get_blocklisted_words(text)
      get_matching_words(WORD_BLOCKLIST, text)
    end

    # Check the given text in two ways to see if it smells like spam.
    # This allows easy movement from troublesome keywords in the
    # blocklist to spammy phrases (in spammy_text) so we get fewer
    # false positives.
    #
    # text - the String to test
    #
    # returns true if the text is spammy, false if not.
    def check_text(text)
      blocklisted?(text) || spammy_text(text).present?
    end

    def drug_list_matches(text)
      drug_match = DRUG_LIST.select do |drug_name|
        # eliminates 'alli' and any other short names likely to false-positive
        next if drug_name.length < 5

        text =~ /#{drug_name}/i
      end
    end

    # Better living through chemistry. But let's don't catch 'specialist',
    # 'ambient', etc., in our net.
    DRUG_LIST = %w[
                    abilify accutane ac[iy]clovir a[cd]iph?ex actos adderall
                    adipex alli alphagan alprazolam ambien(?!t) amlodipine
                    amoxicillin apcalis aricept ashwagandha ativan atrovent
                    azithromycin
                    benadryl benicar benemid blopress
                    capoten cardizem cardura carisoprodol caverta cefadroxil
                    celadrin celebrex celexa (?:[^e]|\b)cialis cipro clomid clonazepam
                    colospa codeine concerta cordarone coreg cymbalta
                    cyto(tec|xan)
                    darvocet deltasone desyrel diazepam diflucan digoxin
                    diovan ditropan doxycycline
                    effexor elavil etodolac evista
                    feldene fioricet flomax(tra)? forzest
                    glucophage
                    haldol hydrocodone kamagra klonopin
                    lamisil lasix levaquin levitra lexapro lipitor lipothin
                    lopressor lorazepam lunesta
                    medrol motrin myambutol
                    naprosyn nexium nolvad(ex|ine) noroxin norvasc novolog
                    oxcarbazepina oxycontin paxil percocet phenergan
                    phentermine phentramin plavix plendil ponstel prazosin
                    predniso(lo)?ne prevacid propecia provigil prozac
                    ritalin rivotril rosuvastatin roxithromycin rumalaya
                    serevent seroquel silagra sildenafil sinequan singulair
                    soma(tropin)? strattera suhagra suprax synthroid
                    tadalafil tada(cip|lis) tamoxifen tofranil topamax
                    triamterene tricor trileptal ultram
                    v-gel valium valtrex vardenafil viagra vicodin
                    wellbutrin xanax xenical
                    zanaflex zetia zithromax zocor zoloft zolpidem zyban
                    zyprexa
                  ]

    # PORN_WORDS_1 and PORN_WORDS_2 are split up because we're trying to
    # limit matches to phrasing that contains one from each group. Not
    # ideal, but it limits false positives and tends to still catch most
    # of the pervs at this time (Jan 2013).
    PORN_WORDS_1 = %w[ hentai illegal innocent kinder l[oi]litas? pedo
                       pedo[fph]+ilia pre[te]{2}en nymph(et|o)?s?
                       teens? underage
                     ]

    PORN_WORDS_2 = %w[ bbs cock cum exotic facials fetish incest japanese
                       models movie nude penis porno? pussy russian? sexy?
                       shocking ukraine
                     ]

    EVENT_WORDS = ["Indy", "MLB", "MMA", "NBA", "NFL", "NHL", "NHRA",
                    "National Basketball", "UFC", "WWE", "WWF", "baseball",
                    "college", "cricket", "episode", "football", "golf",
                    "hd [\s\b-]* tv", "hockey", "kick [\s\b-]* off",
                    "lacrosse", "movie", "olympics?",
                    "premier [\s\b-]* league", "racing", "rugby", "scandal",
                    "sex [\s\b-]* tape", "soccer", "sports", "supercross",
                    "tennis", 'tip [\s\b-]* off', "versus", "vs(?![\s]*code)",
                    "wrestling", "world [\s\b-]* cup"
                  ]

    NAUGHTY_JS = [
      # Catch the JS doing Google Analytics tracking for a very large number
      # of Pages spammer. More details here:
      #
      #   https://github.com/github/github/issues/6433#issuecomment-11480518
      #
      # Original regexp from which this is taken is here:
      #
      #   http://rubular.com/r/sIz8PXHsZ0
      [
        /
          var\s+addAsyncScript .*
          var\s+trackUserAction .*
          addAsyncScript.* (domain|dnsdynamic\.com) .* (count|ad)?\/github\/ .*
          var\s+_gaq\s+=\s+_gaq\s+\|\|\s+\[\]; .*
          _gaq\.push
        /imx,
      ],
      [
        /var .+ t.async .* gud .* aas .*
         \/github\/ .*
         var\s+_gaq\s+=\s+_gaq\s+ \| \| \s+\[\]; .*
         _gaq\.push .*
         (_setCustomVar.*github)
        /imx,
      ],
    ]

    SPAMMY_PHRASES = [

      [
        /\b(live|streaming|season|free|download)\b/imx,
        /\b( #{EVENT_WORDS.join('|')} ) \b /imx,
        /\b(watch|online|free|stream(ing)?|PPV|pay-per-view|click \s* here|internet \s* tv)\b/imx,
      ],

      # Going to the trouble to use the İ here is pretty clear
      [/ WATCH [\b\s]* LİVE /imx],

      # Welcome to our new Swedish spammers!
      [
        /\b Bingo [\b\s]* lottos? \b/imx,
        /\b uppesittarkv[aä]ll \b/imx,
      ],

      # Back to English spam

      [/click \s+ on/imx,
       /Download \s+ Now/imx,
       /Download \s+ ebook \s+ now!?/imx,
      ],

      [/live [\s-]* stream(ing)? \s* (((for \s* )? free) | online)/imx],

      [/live [\s-]* online \s* free \s* stream(ing)?/imx],

      [/free \s+ internet/imx],

      [/adult|bdsm|bondage/imx,
        /dating|sex|parties|personals/imx,
        /free|bdsm|dating/imx,
      ],

      # Better living through chemistry. But let's don't catch 'specialist',
      # 'ambient', etc., in our net.
      [
        /\b(#{ %w[ adipex ambien carisoprodol celebrex cialis evista fioricet
                   glucophage oxycontin viagra wellbutrin xanax zolpidem
               ].join('|') }
           )\b
        /imx,
      ],

      [/\bprescriptions? \s* online\b/imx],

      [/\b (order|buy) [\b\s]* (cheap|online) \b/imx,
        /\b ( #{ DRUG_LIST.join('|') } ) \b /imx,
      ],

      [/\bpokemon\b/imx,
        /\bdownload\b/imx,
        /\b(early|trial|free|rom)\b/imx,
      ],

      [/\b( #{PORN_WORDS_1.join('|')} )\b /imx,
        /\b( #{PORN_WORDS_2.join('|')} )\b /imx,
      ],

      # Here we're looking for combinations of the porn words as one word,
      # so "kindermodels" or "moviepedo"
      [/\b
         ( #{[PORN_WORDS_1, PORN_WORDS_2].flatten.join('|')} )
         ( #{[PORN_WORDS_1, PORN_WORDS_2].flatten.join('|')} )
         \b
        /imx,
      ],

      # These things are getting complicated. These regexps should match if
      # all the objects between word boundaries match the elements in order.
      # Perhaps an example is better.  For the regexp:
      #
      #  /(buy)[\b\s]+(toads|frogs)[\b\s]+(outside)/
      #
      # "buy toads outside" would match, but not "buy outside toads". This is
      # the critical difference from the spammy phrases above, which match if
      # something in content matches each element of a phrase array, without
      # regard for how they're ordered, or if there is stuff in between.
      #
      # Obviously they're part of the same array, but marking the separation
      # here helps make it clearer which are "ordered" and which are not.

      [
        /
          (buy|order)
          [\b\s]+
          (#{ DRUG_LIST.join('|') })
          [\b\s-]+
          (with[\b\s]+)?        # allow 'with' something-or-other
          ([\w-]{0,8}[\b\s]+)?  # allow an intervening word, like 'gel' or 'pills'
          (online)
        /imx,
      ],

      [
        /
          (download|watch)
          [\b\s]+
          # allow up to 4 intervening words, like 'call of duty'
          ([\w-]+[\b\s]+){1,4}
          (online|free)[\b\s-]?(online|free)
        /imx,
      ],

      [
        /
          (download|watch)
          [\b\s]+
          # allow up to 9 intervening words, like 'call of duty'
          ([\w-]+[\b\s]+){1,9}
          # followed by an optional 'versus [5 more words]'
          ( (v\s|vs.?|versus) [\b\s]* ([\w-]+[\b\s]+){1,5} )?
          # followed by at least 2 of 'live', 'streaming', 'online', or 'free'
          ((live|stream(ing)?|online|free)[\b\s-]*){2,}
        /imx,
      ],

    ] # SPAMMY_PHRASES

    SPAMMY_PHRASES_KEY = "spammy_regexes"

    def spammy_phrases_datasource
      @spammy_phrases_datasource = begin
        spam_datasource = SpamDatasource.find_by_name(SPAMMY_PHRASES_KEY)
        spam_datasource ||= begin
          ActiveRecord::Base.connected_to(role: :writing) do
            SpamDatasource.create(
              name: SPAMMY_PHRASES_KEY,
              description: "Spammy Regex phrases for SpamChecker (formerly in redis)",
            )
          end
        end
      rescue ActiveRecord::RecordNotUnique
        retry # rubocop:disable GitHub/UnboundedRetries https://github.com/github/github/issues/134041
      end
    end

    def get_spammy_phrases
      return @phrases if defined? @phrases
      @phrases = GitHub::SpamChecker::SPAMMY_PHRASES.dup
      spammy_phrases_datasource.entries.each do |entry|
        regexps = build_regexps(entry.value)
        # If we didn't get all valid RegExps back, toss the whole phrase.
        next if regexps.empty? || regexps.any? { |r| r.nil? }
        @phrases << regexps
      end
      @phrases
    end

    def build_regexps(phrase_string)
      rcond = Regexp::IGNORECASE | Regexp::MULTILINE | Regexp::EXTENDED
      JSON.parse(phrase_string).map { |r| regex_or_nil(r, rcond) }
    rescue ::Yajl::ParseError, ::JSON::ParserError => e
      notify "Got JSON parse error trying to build Regexps from #{phrase_string}. Exception: #{e.inspect}"
      []
    end

    def regex_or_nil(regexp_str, conditions = 0)
      Regexp.new(regexp_str, conditions)
    rescue RegexpError => e
      notify "Couldn't build valid Regexp from #{regexp_str}. Exception: #{e.inspect}"
      nil
    end

    # A 'phrase' here is an Array of RegExps that travel together.
    def push_spammy_phrase(phrase, key = nil)
      value = phrase.map { |r| r.source }.to_json
      entry = spammy_phrases_datasource.entries.find_by_value(value)
      if entry.nil?
        entry = spammy_phrases_datasource.entries.create value: value,
              additional_context: "Added via SpamChecker#push_spammy_phrase"
      end
      entry
    end

    def push_all_phrases(phrases)
      phrases.each { |phrase| push_spammy_phrase(phrase) }
    end

    def clear_spammy_phrases
      spammy_phrases_datasource.entries.destroy_all
      # With phrases gone make sure we clear up any existing memoization as well
      remove_instance_variable(:@phrases) if defined? @phrases
    end

    def spammy_phrase_count
      spammy_phrases_datasource.entries.count
    end

    def cleanup_text(text)
      return text unless text.present?
      text = GitHub::Encoding.try_guess_and_transcode(text)
      text = GitHub::Unidecode.decode(text)

      text.force_encoding("UTF-8").scrub! unless text.encoding == ::Encoding::UTF_8

      text
    end

    # Check whether the given String is spammy. Operates using word
    # combinations, not single-word blocklisting. This is more useful
    # for things like "streaming NFL online" stuff, since none of those
    # words by themselves should be blocklisted, but that phrase, or even
    # those 3 words together, are a much better indicator that something
    # naughty is afoot.
    #
    # text - String to be checked
    #
    # Returns an Array of Strings that got flagged, or an empty Array if
    # none did.
    def spammy_text(text)
      text = cleanup_text(text)
      matching_phrases = spammy_phrases_that_match(text, get_spammy_phrases)
      matching_phrases.uniq.map { |phrase| phrase.join(" ") }
    end

    def spammy_phrases_that_match(text, spammy_phrases)
      return [] unless text.present?
      text = cleanup_text(text)
      matching_phrases = []
      # This text is spam if there is a match for any of the spammy phrases
      spam_match = spammy_phrases.any? do |phrase|
        # This phrase is a match if there is at least one match for each
        # element of the phrase.
        phrase_matches = phrase.all? do |word|
          unless word.is_a? Regexp
            word = Regexp.new(word, Regexp::IGNORECASE | Regexp::MULTILINE)
          end
          text =~ word
        end
        matching_phrases << phrase if phrase_matches
      end
      if spam_match
        # If we had a match for each element, then the matching phrases matter
        matching_phrases
      else
        # If we didn't have a total match, then the elements that did match
        # are of no interest to us.
        []
      end
    end

    private

    def wiki_edit_items(user)
      GitHub.conduit_client.get_user_wiki_edits(viewer: user, user: user)[:items]
    end
  end
end
