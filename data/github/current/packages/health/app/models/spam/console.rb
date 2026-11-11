# typed: false
# frozen_string_literal: true

# Herewith a collection of useful methods for fighting spam from the
# console.  These aren't of general use, and in fact might confuse or
# clash with general use, so they're not in config/console.rb. Should
# some of them turn out to be generally useful, then they can
# certainly move there.

module Spam
  module Console
    extend self

    def gql(query, target: :internal, context: { viewer: my_bad_self }, variables: {})
      Platform.execute query, target: target, context: context, variables: variables
    end

    def drop_spam_queue_entries_mutation
      @drop_spam_queue_entries_mutation ||= <<-'GRAPHQL'
        mutation($input: DeleteSpamQueueEntriesInput!) {
          deleteSpamQueueEntries(input: $input) {
            accounts {
              ... on User {
                login
              }
              ... on Organization {
                login
              }
              ... on Bot {
                login
              }
            }
          }
        }
      GRAPHQL
    end

    def drop_spam_queue_entries(entries)
      puts pink("I'm in graphql dsqe with #{entries.count} entries to drop")
      puts red("TOO MANY") if entries.count > 100
      grids = entries.map { |t| t.respond_to?(:global_relay_id) ? t.global_relay_id : t }
      variables = {
        "input" => {
          "entryIds" => grids,
        },
      }
      puts "About to drop it"
      results = gql drop_spam_queue_entries_mutation, variables: variables
      puts "Back from dropping it"
      results
    end

    def resolve_spam_queue_entry_grids_mutation
      @resolve_spam_queue_entry_grids_mutation ||= <<-'GRAPHQL'
        mutation ($input: ResolveSpamQueueEntriesInput!) {
          resolveSpamQueueEntries(input: $input) {
            accounts {
              ... on User {
                login
                stafftoolsInfo {
                  isHammy
                  isSpammy
                  isInPossibleSpammerQueue
                }
              }
            }
          }
        }
      GRAPHQL
    end

    def resolve_entry_grids_with_classification(entry_grids, classification, reason = nil)
      variables = {
        "input" => {
          "origin" => Spam::Origin.console_origin.to_s,
          "resolutions" => entry_grids.collect do |entry_grid|
            {
              "id" => entry_grid,
              "classification" => classification,
              "reason" => reason,
            }
          end,
        },
      }
      gql resolve_spam_queue_entry_grids_mutation, variables: variables
    end

    def resolve_entries_with_classification(entries, classification, reason = nil)
      entry_grids = entries.compact.collect do |entry|
        entry.is_a?(SpamQueueEntry) ? entry.global_relay_id : entry
      end
      resolve_entry_grids_with_classification entry_grids, classification, reason
    end

    def resolve_entries_as_hammy(entries)
      resolve_entries_with_classification entries, "HAMMY"
    end

    def resolve_entries_as_unknown(entries)
      resolve_entries_with_classification entries, "UNKNOWN"
    end

    def spam_queue_entries_for_users_query
      @spam_queue_entries_for_users_query = <<-"GRAPHQL"
        query SpamQueueEntriesForGrids($ids: [ID!]!, $queueId: ID!) {
          nodes(ids: $ids) {
            id
            ...on User {
              stafftoolsInfo {
                isInPossibleSpammerQueue
                spamQueueEntry(spamQueueId: $queueId) {
                  id
                  accountLogin
                }
              }
            }
            ...on Organization {
              stafftoolsInfo {
                isInPossibleSpammerQueue
                spamQueueEntry(spamQueueId: $queueId) {
                  id
                  accountLogin
                }
              }
            }
          }
        }
      GRAPHQL
    end

    # Accepts an array of Users (or Orgs) and returns a minimal bit of info
    # for each, including whether that object is on the PSQ and the GRID of
    # its SpamQueueEnetry if so.
    def spam_queue_entries_for_users(users_or_orgs, queue: Spam.possible_spammer_queue.spam_queue)
      variables = { "ids": users_or_orgs.collect(&:global_relay_id),
                    "queueId": queue.global_relay_id,
                  }
      response = gql spam_queue_entries_for_users_query, variables: variables
      response.data.dig("nodes").collect { |t| t.dig "stafftoolsInfo", "spamQueueEntry" }.compact
    end

    # Flag a User or an Array of Users as spammy, with a default
    # reason and a default actor (@erebor) set for audit logging.
    def flag_these(u, reason = "Fake account spam")
      # Convenience so I can pass a single user in here
      u = Array(u)
      to_drop = []
      u.select { |us| !us.spammy }.each do |this_user|
        to_drop << this_user
        this_user.mark_as_spammy(reason: reason, actor: my_bad_self)
      end
      drop_queue_entries_by_account to_drop.collect(&:global_relay_id)
    end

    # Flag a User or an Array of Users as spammy, with a default
    # reason and a default actor (@erebor) set for audit logging,
    # EVEN if that user is invalid and normal mark_as_spammy calls
    # won't work.
    def flag_these_the_hard_way(u, reason = "Fake account spam")
      # Convenience so I can pass a single user in here
      u = Array(u)
      u.select { |us| !us.spammy }.each do |us|
        us.mark_as_spammy(reason: reason, actor: my_bad_self)
        if !(us.reload.spammy || us.never_spammy?)
          us.update_attribute :spammy_reason, "#{reason} by @#{actor.login}"
          us.update_attribute :spammy, true
        end
      end
      Spam.possible_spammer_queue.drop_these(u)
      blacklist_user_ip(u.first) if u.count > 5
    end

    # Unflag an arbitrarily-large group of accounts
    def unflag_these(u)
      Array(u).select { |us| us.spammy }.each do |user|
        user.mark_not_spammy actor: my_bad_self
      end
      Spam.possible_spammer_queue.drop_these(u)
      nil
    end

    # @erebor
    def my_bad_self
      @my_bad_self ||= User.find_by_login("erebor")
    end

    # Quick way to add a staff note to a given user from the console.
    def add_staff_note(user, note, notary = my_bad_self)
      return false unless user.is_a?(User) && notary.is_a?(User)
      if note.blank?
        puts "Nope. Not adding an empty StaffNote."
        return false
      end
      user.staff_notes.create(note: note, user: notary)
    end

    # Given a User or Array of Users, add the #last_ip for each of
    # them to the IP blacklist.
    def blacklist_user_ip(user, params = nil)
      params ||= { verbose: true }
      # Convenience so I can pass an array of Users in here
      user = user.first if user.is_a? Array
      blacklist_these_ips(user.last_ip, params)
    end

    # Add the given IP addresses to the IP blacklist.
    def blacklist_these_ips(addresses, params = nil)
      params ||= { verbose: true }
      Spam::ip_denylist(addresses, params)
    end

    # Set and/or retrieve target_width
    def target_width(new_width = nil)
      if new_width
        @target_width = new_width
      else
        @target_width ||= 75
      end
    end

    def count_summary(count)
      output = []
      if count.values.sum == 0
        output << "\t[No Activity]"
      else
        output << "\tRepos: #{count[:repos]}\tIssues: #{count[:issues]}\tGists: #{count[:gists]}\tPRs:       #{count[:pull_requests]}\tFollowers/Following: #{count[:followers]}/#{count[:following]}"
        output << "\tComments:\tIssue:  #{count[:issue_comments]}\tGist:  #{count[:gist_comments]}\tCommit:    #{count[:commit_comments]}\tWiki Edits: #{count[:wiki_edits]}\tStars: #{count[:stars]}"
      end
      output
    end

    def org_summary(user)
      org_details = ""

      if user.organization?
        if user.admins.any?
          org_details += "Admins: #{purple(user.admins.count)}"
          org_details += "\tAdmin: #{user.admins.first.login}\t(#{user.admins.first.email})"
        else
          org_details += "Admins: 0"
        end
      else
        org_count = user.organizations.count

        case org_count
        when 0
          org_details += "Orgs: 0"
        when 1
          org_details += "Orgs: #{user.organizations.first.login}"
        else
          org_details += "Orgs: #{purple(org_count)}"
        end
      end

      org_details
    end

    def wiki_pages_summary(wiki)
      output = []
      if wiki.exist?  # Only way for it to exist? is if a page has been created
        if wiki.default_oid.nil?
          puts "BOGUS wiki on #{wiki.repository.nwo} ; exists but no default_oid. Skipping."
        else
          output << wiki.pages.latest(1, 10).collect(&:title)
        end
      end
      output
    end

    def dump_issues_that_look_sketchy(issues)
      result = []
      Array(issues).last(5).each do |issue|
        r = dump_issue_if_sketchy_to_content_classifier(issue)
        r = dump_issue_if_sketchy_to_akismet(issue)            if r.empty?
        result.concat r unless r.empty?
      end
      result
    end

    def dump_issue_if_sketchy_to_content_classifier(issue)
      result = []
      score = issue_content_classification issue
      unless score == "NONE"
        result << "\t%d\t%s\t%s" % [issue.id, invert_gray(score), issue.permalink]
        result << "\t%s" % issue.body.to_s[0..60]
      end
      result
    end

    def dump_issue_if_sketchy_to_akismet(issue)
      result = []
      return result unless [issue.title, issue.body].join("\n").length > 15
      akismet_says = akismet_issue(issue)
      if akismet_says
        result << "\t%d\tAkismet said true\t%s" % [issue.id, issue.permalink]
        result << "\t%s" % issue.body.to_s[0..60]
      end
      result
    end

    def has_verified_email?(user)
      return false unless user
      user.emails.
        reject { |t| t.email =~ /\A[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@users\.noreply\.github\.com\z/ }.
        any? { |t| t.state == "verified" }
    end

    # Dump a summary of activity for the given User to the console.
    def activity_summary(user)
      output = []

      if defined?(spam_queue_entry_for_login) == "method"
        if sqe_grid = spam_queue_entry_for_login(user)
          db_id = Platform::Helpers::NodeIdentification.from_global_id(sqe_grid).last
          output << blue("%s SQE: %d (grid: %s)" % ["\t\t", db_id, sqe_grid])
        end
      else
        if sqe = q.spam_queue.entry_for_user(user)
          output << blue("%s SQE: %d (grid: %s)" % ["\t\t", sqe.id, sqe.global_relay_id])
        end
      end
      begin
        count = GitHub::SpamChecker.activity_count(user)
        adjust_for_color = 10
        login_line = "[#{user.id}] #{user.login} (#{user.email || blue(user.billing_email)})"
        login_line << " #{green('+')}" if has_verified_email?(user)
        status_line = user_status_summary(user, show_plan: true)
        login_line << " " << status_line
        adjust_for_color += (status_line.count("\e") * 9 / 2) + 1
        llen = login_line.length
        created = "Created: #{blue(time_ago_in_words(user.created_at) + ' ago')}"
        clen = created.length
        spaces = [1, (target_width + adjust_for_color) - (llen + clen)].max
        login_line << "#{' ' * spaces}#{created}"
        if user.suspended?
          login_line << "    #{invert_yellow('Suspended')}"
        end
        output << login_line

        # Organization and last_ip line
        org_output = org_summary(user)
        llen = org_output.length
        last_ip = "Last IP: #{blue(user.last_ip)}"
        clen = last_ip.length
        clen -= 10 unless user.last_ip.blank?
        # adjust 11 positions for leading tab and spaces
        spaces = [1, target_width - 11 - (llen + clen)].max
        org_line = "\t   " + org_output
        org_line << "#{' ' * spaces}#{last_ip}"
        output << org_line
        output << "\tDescription: #{user.description.to_s[0..55]}\n" if user.respond_to?(:description)

        output << "%s %s" % [user.spammy? ? red("S\t") : "\t", (user.spammy_reason || "...")]
        output << count_summary(count)

        output.concat oauth_summary(user)

        output.concat profile_summary(user.profile)
        user.repositories.first(2).each do |repo|
          output.concat repo_summary(repo)
          if user.repositories.count < 3
            output.concat wiki_pages_summary(repo.unsullied_wiki)
          end
        end

        output.concat dump_issues_that_look_sketchy(user.issues)

        if user.repositories.empty? && count[:wiki_edits] > 0
          output.concat collect_edits user
        end

        staff_notes = staff_notes_summary(user)
        if staff_notes.present?
          output << "\n" + blue("Staff Notes:")
          output.concat staff_notes
        end

        SpamPattern.matches_for(user).each do |sp|
          output << "SP #{sp.id} - #{sp.class_name}.#{sp.attribute_name}"
        end
      rescue Faraday::ConnectionFailed, NoMethodError => e
        output << "#{invert_yellow('RESCUED:')} #{e}"
      end
      output.join("\n")
    end

    def has_non_github_oauth_accesses?(user)
      return false unless user
      user.oauth_accesses.reject { |t| t.application.nil? || t.application.github_owned? }.present?
    end

    def oauth_summary(user, number_to_show = 5)
      return [] unless user
      output = []
      apps = user.oauth_accesses.includes(:application).
              reject { |t| t.application.nil? || t.application.github_owned? }.
              collect(&:application).uniq.compact
      total_apps_count = apps.count
      apps.first(number_to_show).each do |app|
        if app.respond_to? :domain
          url = app.domain
        elsif app.respond_to? :url
          url = app.url
        else
          url = "Can't get URL from class #{app.class}"
        end
        interval = user.oauth_accesses.find { |t| t.application_id == app.id }.created_at - user.created_at
        if interval < 60
          interval = blue("(%-.01fs)" % interval)
        else
          interval = " " * 7
        end
        output << "App: %-8d %s %s\t\t%s" % [app.id, interval, app.name, aqua(url)]
      end
      if total_apps_count > number_to_show
        output << "...and %d more" % [total_apps_count - number_to_show]
      end
      output
    end

    def faradapter
      @f ||= Faraday.new(Spam::ContentBasedClassifier::URL,
                         headers: { "Content-Type" => "application/json" })
    end

    def content_classification(model, content_id:, content:, debug: false, fallback: nil)
      max_allowed_retries = 3
      begin
        retries ||= 0

        payload = { data: [{ content_id: 1, content: content }] }
        response = faradapter.post("/predict/#{model}", payload.to_json)

        if response.status == 200
          parsed_body = JSON::parse(response.body)
          if debug
            parsed_body
          else
            parsed_body.dig("results", 0, "threat_level") || false
          end
        end
      rescue Faraday::Error, Faraday::ConnectionFailed => error
        if (retries += 1) <= max_allowed_retries
          Spam.stats_increment("retry_content_classification_request", tags: ["retry_count:#{retries}"])
          retry
        end
        fallback
      end
    end

    def url_content_classification(url, debug: false)
      content_classification("user_website_url", content_id: 1, content: url)
    end

    def gist_comment_content_classification(comment, debug: false)
      content_classification("gist_comment", content_id: comment.id, content: comment.body)
    end

    def issue_comment_content_classification(comment, debug: false)
      content_classification("issue_comment", content_id: comment.id, content: comment.body)
    end

    def issue_content_classification(issue, debug: false)
      content = [issue.title, issue.body].join ": "
      content_classification("issue", content_id: issue.id, content: content)
    end

    def repo_spam_classification(repo, debug: false)
      content = [repo.name, repo.description].join ": "
      content_classification("repository", content_id: repo.id, content: content)
    end

    def repo_spam_class(repo, verbose = false)
      @repo_results_cache ||= {}
      @repo_results_cache_key_queue ||= []

      repo = dat(repo) if repo.is_a? String
      puts "Repo is #{repo.nwo}" if verbose
      key = repo.nwo
      puts "key is #{key}" if verbose
      # Keep it trimmed
      while @repo_results_cache_key_queue.size > 1000
        puts "Trimming repo spam results cache" if verbose
        @repo_results_cache.delete @repo_results_cache_key_queue.shift
      end

      if @repo_results_cache[key]
        puts "In repo_naughty: Using cached results for #{repo.nwo}" if verbose
        @repo_results_cache[key]
      else
        result = nil
        puts "In repo_naughty: Looking up Repo results for #{repo.nwo}" if verbose
        puts "Calling repo_spam_classification on #{repo.nwo}" if verbose
        result = repo_spam_classification(repo)
        puts "Result was #{result} from r_d_s_c" if verbose

        # Store and return the answer
        puts "Returning result #{result}" if verbose
        @repo_results_cache[key] = result
      end
    end

    def repo_summary(repo)
      output = []
      return output unless repo
      min_desc_len = 20
      available_space = [0, target_width - repo.name.length - 4].max
      desc_len = [min_desc_len, available_space].max
      spam_class = repo_spam_class(repo)
      if spam_class == "WARNING"
        spam_class_letter = "%s " % yellow("[W]")
      elsif spam_class == "CRITICAL"
        spam_class_letter = "%s " % red("[C]")
      else
        spam_class_letter = ""
      end
      fork_state = repo.fork? ? blue("F") : " "
      output << "%s%s :%s: %s" % [spam_class_letter, repo.name, fork_state, repo.description.to_s.first(desc_len)]
      output << "  [#{repo.id}]\t#{repo.permalink}"
      output
    end

    def user_profile_spam_classification(user, debug: false)
      payload = { data: [{ content_id: user.id, content: user.profile ? user.profile.bio : nil }] }
      return "none" unless payload[:data][0][:content].present?

      r = faradapter.post("/predict/user_profile", payload.to_json)
      if r.status == 200
        parsed_body = JSON::parse(r.body)
        if debug
          parsed_body
        else
          if parsed_body["results"].first
            parsed_body["results"].first["threat_level"]
          else
            false
          end
        end
      else
        false
      end
    end

    def profile_naughty(user, verbose = false)
      @profile_results_cache ||= {}
      @profile_results_cache_key_queue ||= []

      user = dat(user) if user.is_a? String
      return false unless user.profile.present?

      key = user.login
      # Keep it trimmed
      while @profile_results_cache_key_queue.size > 1000
        puts "Trimming profile results cache" if verbose
        @profile_results_cache.delete @profile_results_cache_key_queue.shift
      end

      if @profile_results_cache[key]
        puts "In profile_naughty: Using cached results for #{user.login}" if verbose
        @profile_results_cache[key]
      else
        result = nil
        puts "In profile_naughty: Looking up Profile results for #{user.login}" if verbose
        tries = 3
        while tries > 0
          begin
            result = user_profile_spam_classification(user)
            break
         rescue Faraday::ConnectionFailed => e
           if (4 - tries) > 1
             puts "Rescued Mr. Faraday in profile_naughty. Trying again (attempt ##{4 - tries})"
             puts "Error was #{e}"
           end
          end
          tries -= 1
        end
        # Store and return the answer
        if %w[CRITICAL WARNING].include? result
          @profile_results_cache[key] = result
        else
          @profile_results_cache[key] = false
        end
      end
    end

    def user_status_summary(user, options = {})
      options.reverse_merge(show_plan: false)
      status = ""
      if user.paid_plan?
        status << green("$")
        status << green(" (#{user.plan.name})") if options[:show_plan]
      else
        status << " "
      end
      begin
        status << (user.spammy? ? red("S") : " ")
        status << ((user.never_spammy? && !user.paid_plan?) ? blue("N") : " ")
        status << (has_blacklisted_payment_method?(user) ? invert_yellow("B") : " ")
        status << (user.suspended? ? invert_gray("S") : " ")
        status << (has_non_github_oauth_accesses?(user) ? aqua("O") : " ")
        profile_rating = profile_naughty(user)
        if profile_rating.to_s == "WARNING"
          status << pink("P")
        elsif profile_rating.to_s == "CRITICAL"
          status << red("P")
        elsif user.profile.present?
          status << gray("P")
        else
          status << " "
        end
      rescue Faraday::ConnectionFailed, NoMethodError => e
        status << "#{invert_yellow('RESCUED:')} in user_status_summary: #{e}"
      end
      status
    end

    def profile_summary(profile)
      return [] unless profile

      output = [blue("\t\t\t\t--- Profile [%08d]---" % profile.id)]
      if profile.name || profile.email
        output << "\tName: %-30s Email: %-30s" % [profile.name, profile.email]
      end
      if profile.bio.present?
        output << "\tBio: #{profile.bio[0..80]}"
      end
      if profile.blog
        output << "\tBlog: #{profile.blog}"
      end
      if profile.company || profile.location
        output << "\tCompany: %-40s Location: %-35s" % [profile.company, profile.location]
      end
      if profile_naughty(profile.user)
        output << red("\t%s" % ("^" * 50))
      end
      output
    end

    # Return a quick summary of StaffNotes created by actual staff (not
    # the 'github' Org user that various rescue and recovery operations
    # uses to add StaffNotes).
    def staff_notes_summary(user)
      user.staff_notes.reject { |sn| sn.user_id == 9919 }.collect do |snote|
        blue("\t#{snote.created_at}\t\t#{snote.user.login}") +
        "\n#{snote.note}"
      end
    end

    # Dump a summary of activity for the given User to the console.
    def activity_summary_short(user)
      count = GitHub::SpamChecker.activity_count(user)
      output = []
      output << "[#{user.id}]"
      output << "%s" % (user.spammy ? red(user.login) : user.login)
      output << "(%-20s)" % user.email
      if count.values.sum == 0
        output << " [No Activity]"
      else
        output << "  R: #{count[:repos]}  I: #{count[:issues]}  G: #{count[:gists]}  F: #{count[:followers]}  PR: #{count[:pull_requests]}"
        output << "  IC: #{count[:issue_comments]}  GC: #{count[:gist_comments]}  CC: #{count[:commit_comments]}"
      end
      output.join(" ")
    end

    # This is the next generation of the gmail_flood_account dirtbag.
    # His first cut here is to return to the quatro login and mailbox
    # naming model, but his domain names are now all over the place,
    # and include live.com, yahoo.com, gmail.com, charter.net, att.net,
    # verizon.net, mac.com(!), and a ton of rr.com subdomains, and
    # many more. So now we're going to have to work some from context.
    def nextgen_flood_account_login_and_email(user)
      return false unless user.email.present?
      login = user.login
      mailbox = user.email.to_s.split("@").first
      mailbox !~ /#{Regexp.escape(login)}/ &&
        mailbox !~ /#{Regexp.escape(login[0..login.length - 4])}/ &&
        login !~ /#{Regexp.escape(mailbox)}/ &&
        login !~ /#{Regexp.escape(mailbox[0..mailbox.length - 4])}/ &&
        [login, mailbox].join("#") =~ /\A([a-z]{4,11})([a-z0-9]{4,11})#\1([a-z0-9]+)\z/ &&
          (second = $2) && (third = $3) &&
          (second.length >= 4 && third.length >= 4) &&
          mailbox !~ /#{$2}/ &&
          GitHub::Levenshtein.similarity(second, third) < 0.30
    end

    def nextgen_flood_account(user, verbose = false)
      return false unless nextgen_flood_account_login_and_email(user)
      return true if gmail_flood_account_context(user)
      # Now check if the last one shares our login/email pattern
      last_one = the_one_before_this(user, how_many: 5, days_ago: 30, wide: true)
      last_one && nextgen_flood_account_login_and_email(last_one)
    end

    ## Instantiation:

    # new users, 50 per page
    # filter = PagedModelFilter.new(scope: User, sentinel: User.last, limit: 50)
    # Filtering:

    # discard users with even IDs
    # filter.skip { |u| (u.id % 2).zero? }

    ## Paging:

    # grab the next page of results, possibly making multiple queries
    # filter.advance  # => [an, array, of, users]

    # look at the current page of results without advancing
    # filter.models  # => [an, array, of, users]

    # Iterate through pages of ActiveRecord models by ID, optionally filtering.
    class PagedModelFilter
      attr_reader :filters
      attr_reader :limit
      attr_reader :progress_key
      attr_reader :scope
      attr_reader :sentinel
      attr_reader :last_id

      attr_accessor :verbose

      attr_accessor :models
      protected :models=

      def initialize(scope:, sentinel:, limit: 30, progress_key:)
        @last_id = sentinel.id
        @scope   = scope
        @limit   = limit
        @filters = []
        @progress_key = progress_key
        @models  = [].freeze
      end

      def save_progress(user_id)
        return unless @progress_key
        Spam::Kv.store.set(@progress_key, user_id.to_s)
      end

      def advance(limit: self.limit)
        last_id = self.last_id
        models = []

        print " " * limit + "|\r" if verbose
        load_size = limit * 2
        until models.size == limit
          candidates = scope.where("#{scope.table_name}.id > ?", last_id).
            order(:id).limit(load_size).to_a # avoid a COUNT for the empty? call below

          break if candidates.empty?

          save_progress(candidates.first.id - 1)

          candidates.each do |model|
            last_id = model.id

            next if skip?(model)
            print "*" if verbose
            models << model

            if models.size == limit
              puts if verbose
              break
            end
          end
        end

        self.last_id = last_id
        self.models = models.freeze
      end

      def last_id=(id)
        # Make sure we get set to a (relatively) sane id
        @last_id = [1, id].max
      end

      def skip(&block)
        filters << block
        nil
      end

      def skip?(model)
        filters.any? { |skip| skip.call(model) }
      end
    end  # PagedModelFilter

    # Convenience wrappers

    def has_blacklisted_payment_method?(user)
      BlacklistedPaymentMethod.exists_for_account?(user)
    end

    def collect_edits(user, count = 5)
      output = []
      GitHub::SpamChecker.wiki_edits(user).last(count).each do |event|
        next if event.updates.empty?

        page = event.payload[:pages].first
        sha = page[:sha]
        output << "[#{blue(page[:action])}] #{page[:html_url]}/_compare/#{sha}^...#{sha}"
      end
      output
    end

    # Pretty, pretty colors.
    def colorize(str, color_code)
      "\e[#{color_code}m#{str}\e[0m"
    end

    def red(str);    colorize(str, 31); end
    def green(str);  colorize(str, 32); end
    def yellow(str); colorize(str, 33); end
    def blue(str);   colorize(str, 34); end
    def pink(str);   colorize(str, 35); end
    def purple(str); colorize(str, 35); end
    def aqua(str);   colorize(str, 36); end
    def gray(str);   colorize(str, 37); end

    def invert_red(str);    colorize(str, 41); end
    def invert_green(str);  colorize(str, 42); end
    def invert_yellow(str); colorize(str, 43); end
    def invert_gray(str);   colorize(str, 47); end

  end # module Console
end # module Spam
