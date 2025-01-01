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

    def drop_spam_queue_entry(entry)
      drop_spam_queue_entries(Array(entry))
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

    # Only call this for groups with the same spammy reason please.
    def resolve_entries_as_spammy(entries, reason)
      resolve_entries_with_classification entries, "SPAMMY", reason
    end

    def resolve_entries_as_unknown(entries)
      resolve_entries_with_classification entries, "UNKNOWN"
    end

    # Cannot yet easily aggregate a lot of these, as the reason often varies
    # entry by entry.
    def resolve_entry_as_spammy(entry, reason)
      resolve_entries_as_spammy Array(entry), reason
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

    # Accepts a User (or Org) object and returns a minimal bit of info
    # including whether that object is on the PSQ and the GRID of its
    # SpamQueueEntry if so.
    def spam_queue_entry_for_user(user_or_org)
      spam_queue_entries_for_users([user_or_org]).first
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

    # Flag an arbitarily-large group of accounts but don't trip the IP blacklist
    def qflag_these(u, reason = "Fake account spam")
      u = Array(u)
      ((u.count / 5) + 1).times do
        flag_these u.reject(&:spammy)[0..4], reason
      end
    end
    alias :qf :qflag_these

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

    # Blacklist the IP from which a User (or each of an Array of
    # Users) was created.
    def origin_blacklist(u)
      blacklist_these_ips Array(u).map { |t| find_creation_ip_address(t) }
    end

    # Remove the IP address for a User (or the first of an Array of
    # Users) from the IP blacklist.
    def unblacklist_user_ip(user)
      Spam::ip_undenylist(Array(user).first.last_ip)
    end

    # Given a User or login name, return the User, all other Users
    # with the same #last_ip address, and an array of their logins.
    def get_crew_from(user)
      user = the(user) if user.is_a? String
      (u, logins) = get_accomplices(user)
      [user, u, logins]
    end

    # Grab the next spammer candidate from the PSQ and return his and
    # his whole crew's info.
    def get_next_crew(params = nil)
      params ||= {}
      login = params[:login] || Spam.possible_spammer_queue.get_next(params)
      get_crew_from(login)
    end

    # Given a User, return an array of Users with the same #last_ip
    # address, and an array of all their logins.
    def get_accomplices(user, verbose = true)
      if user.last_ip
        u = User.by_ip(user.last_ip)
      else
        u = [user]
      end

      logins = u.collect(&:login)

      if verbose
        puts
        puts logins.inspect
        puts "\n#{user.login} - #{user.email} \t (#{logins.index(user.login) + 1} of #{logins.count}, #{u.count(&:spammy) * 100 / u.count}% spammy) spammy: #{user.spammy} #{(' Reason: ' + user.spammy_reason) unless user.spammy_reason.blank?}"
      end
      [u, logins]
    end

    # Dump a quick summary of the next `number` logins on the spammer
    # candidate queue.
    def rpeek(number = 10)
      candidates = Spam.possible_spammer_queue.peek(number)
      candidates.each_with_index do |candidate, idx|
        if user = the(candidate)
          (u, logins) = get_accomplices(user, false)
          # Have to space it, then colorize it, because the escape sequences
          # muck with the string length.
          login = "%-30s" % user.login
          login = user.spammy ? red(login) : login
          email = user.spammy ? red(user.email) : user.email
          puts "[%2d] [%8d] %s (%3d) - %s" %
                [idx + 1, user.id, login, logins.count, email]
        else
          puts "[%2d] [   N/A  ] #{red(candidate)}" % [idx + 1]
        end
      end
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

    def dump_repos(user)
      output = []
      user.repositories.each do |repo|
        output.concat repo_summary(repo)
      end
      puts output
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

    def repo_naughty(repo, verbose = false)
      repo_spam_class(repo) == "CRITICAL"
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

    def like_login(login_pattern, days = 3)
      puts "Looking back %d days for '%s'" % [days, login_pattern]
      v = User.not_spammy.where(["created_at > ? and login like '#{login_pattern}'", days.days.ago])
      puts "Found #{v.count} matching logins"
      v
    end

    def like_email(email_pattern, days = 3)
      puts "Looking back %d days for '%s'" % [days, email_pattern]
      ue = UserEmail.not_spammy.where(["user_emails.created_at > ? and email like '#{email_pattern}'", days.days.ago])
      puts "Found #{ue.count} matching emails"
      ue
    end

    # For the given Gist, return the total number of files.
    def gist_file_count(gist)
      gist.files_with_path.count
    end

    # For the given Gist, return the first 1000 or so bytes of data
    # from its first file.
    def gist_sample_data(gist, bytes = 1400)
      gist.files_with_path.first.first.data[0..bytes - 1]
    end

    def tail_gists(options = nil)
      options ||= {}
      old_gist       = options[:gist] || Gist.last
      delay          = options[:delay] || 2
      delay_method   = options[:delay_method]
      quiet          = options[:quiet]
      show_anonymous = options[:show_anonymous]
      show_spammy    = options[:show_spammy]
      base = show_spammy ? Gist : Gist.not_spammy
      base = base.joins(:user)
      conditions = "gists.id > ?"
      conditions << " AND gists.user_id IS NOT NULL" unless show_anonymous

      loop do
        new_gist = base.where([conditions, old_gist.id]).first
        if new_gist
          begin
            unless quiet
              puts "\n" + "=" * 75
              gist_snip new_gist
            end
            old_gist = new_gist
            if block_given?
              puts unless quiet
              yield new_gist
              puts unless quiet
            end
          rescue GitRPC::RepositoryOffline, GitRPC::InvalidRepository => e
            puts "In tail_users: Git repo not available; skipping. Msg was [#{e}]"
            next
          end
        end
        if delay_method.is_a? Proc
          if new_gist
            gap = Gist.last.id - new_gist.id
          else
            gap = 0
          end

          delay = delay_method.call(gap)
        end
        sleep delay
      end
    end

    def build_gist_snippet(gist)
      output = []
      if user = gist.user
        user_string = user.to_s
        if user.spammy?
          user_string = red(user_string)
        elsif user.hammy?
          user_string = blue(user_string)
        end
      else
        user_string = "Anonymous"
      end
      begin
        files_with_path = gist.files_with_path
        output << "Gist %-8s Files: %2d   [%-7s]  %s  On: %s" %
                  [gist.id, files_with_path.count,
                   gist.public? ? "public" : "private",
                   user_string,
                   gist.created_at.to_formatted_s(:db)]
        output << gist.url.to_s
        output << ""

        # Only check the first five files
        files_with_path[0..4].each do |blob, path|
          filename = path[0..56]
          if path.length > 57
            filename += "." * 3
          end
          fn_length = filename.length
          padding = (60 - fn_length) / 2
          padding = 1 if padding < 0
          output << "\nSnippet: #{'*' * padding} #{filename} #{'*' * padding}"
          if blob.info["binary"]
            output << blue("   [Binary]")
          else
            # Take the first 8 lines max
            output << blob.data[0..150].split("\n").first(8).join("\n")
          end
        end
      rescue GitRPC::Failure, GitRPC::RepositoryOffline, GitHub::DGit::UnroutedError => e
        output << "GitRPC Failure retrieving files for Gist #{gist.id}: #{e}"
      end
      output.map { |o| o.force_encoding("UTF-8").scrub! }.join("\n")
    end

    def gist_snip(src = Gist.last)
      src = src.gists.last if src.is_a? User
      puts build_gist_snippet(src)
    end

    # The prolific login-login spammer of 2015 does logins like 'zieme-zion',
    # and thousands of them.  So I've captured a bunch of the pieces he builds
    # logins from, and put them in a queue to see if we can catch them at
    # creation time.
    def login_login_spammer_parts_queue_key
      "login_login_spammer_parts"
    end

    def login_login_spammer_parts_queue
      @llspq ||= Spam::Queue.new(login_login_spammer_parts_queue_key, "login-login spammer parts")
    end

    def login_login_add_part(login_part)
      login_login_spammer_parts_queue.push login_part
    end

    def login_login_spammer_part?(login_part)
      login_login_spammer_parts_queue.is_member? login_part
    end

    def login_login_parts_count
      login_login_spammer_parts_queue.size
    end

    def missing_login_login_parts(login)
      login = login.login if login.is_a? User
      login_parts = login.split("-")
      if login_parts.count == 2
        login_parts.reject { |t| login_login_spammer_part? t }
      else
        []
      end
    end

    def count_login_login_parts(login)
      login = login.login if login.is_a? User
      login_parts = login.split("-")
      if login_parts.count == 2
        login_parts.count { |t| login_login_spammer_part? t }
      else
        -1
      end
    end

    def comment_spammer_queue_key
      "possible_comment_spammer_logins"
    end

    def comment_spammer_queue
      @csq ||= Spam::Queue.new(comment_spammer_queue_key, "Console: possible comment spammer logins")
    end

    def clear_from_comment_queue(u)
      Array(u).each do |user|
        comment_spammer_queue.drop_this user.login
      end
      nil
    end

    def get_next_comment_crew(params = nil)
      params ||= {}
      login = params[:login] || get_comment_candidate
      get_crew_from(login)
    end

    def take_a_break(delay = nil)
      delay = 0.75 if delay.to_f <= 0.01
      sleep(delay)
    end

    def get_comment_candidate
      if (login = comment_spammer_queue.peek)
        comment_spammer_queue.drop_this login
      end
      login
    end

    # Add a login to the comment spammer candidate list for evaluation
    # later.
    def push_comment_candidate(login, params = {})
      comment_spammer_queue.push login
    end

    def is_comment_candidate?(login)
      comment_spammer_queue.is_member? login
    end

    def tail_gist_comments(options = nil)
      options    ||= {}
      old_comment  = options[:comment] || GistComment.last
      delay        = options[:delay] || 2
      delay_method = options[:delay_method]
      quiet        = options[:quiet]
      show_spammy  = options[:show_spammy]
      base = show_spammy ? GistComment : GistComment.not_spammy
      base = base.joins(:user)

      loop do
        new_comment = base.where(["gist_comments.id > ?", old_comment.id]).first

        if new_comment
          dump_gist_comment new_comment unless quiet
          old_comment = new_comment
          puts unless quiet
          yield new_comment if block_given?
          puts unless quiet
        end
        if delay_method.is_a? Proc
          if new_comment
            gap = GistComment.last.id - new_comment.id
          else
            gap = 0
          end

          delay = delay_method.call(gap)
        end
        sleep delay
      end
    end

    def dump_gist_comment(comment)
      user = comment.try(:user)
      puts "v" * 70
      puts dump_user_info(user)
      puts "-" * 70
      puts "GC #{comment.id} from Gist #{comment.gist.id} - #{comment.gist.url}"
      puts "*" * 70
      puts snip_text comment.body
      puts "^" * 70
    end

    def tail_issues(options = nil)
      options ||= {}
      old_issue    = options[:issue] || Issue.last
      delay        = options[:delay] || 2
      delay_method = options[:delay_method]
      quiet        = options[:quiet]
      show_spammy  = options[:show_spammy]
      skip_whitelisted = options[:skip_whitelisted]
      base = show_spammy ? Issue : Issue.not_spammy
      base = base.joins(:user)

      loop do
        new_issue = base.public_scope.where(["issues.id > ?", old_issue.id]).first

        if new_issue
          old_issue = new_issue
          next if new_issue.user.nil?
          # GoogleCodeExporter (9614759), dependabot,and dependabot-preview
          # Issues we can skip for now
          next if [9614759, 27856297, 49699333].include? new_issue.user.id

          next if skip_whitelisted && new_issue.user.hammy?

          dump_issue new_issue unless quiet

          if block_given?
            puts unless quiet
            yield new_issue
            puts unless quiet
          end
        end
        if delay_method.is_a? Proc
          if new_issue
            gap = Issue.last.id - new_issue.id
          else
            gap = 0
          end

          delay = delay_method.call(gap)
        end
        sleep delay
      end
    end

    def dump_issue(issue)
      user = issue.user
      repo = issue.repository
      puts "v" * 80
      puts "User %9d  %-39s\tRepo: %s" %
           [user.id, user.spammy? ? red(user.login) : blue(user.login),
            blue(repo&.nwo.nil? ? "N/A" : repo.nwo)]
      link = repo&.private? ? purple(issue.permalink) : issue.permalink
      puts "Issue #{issue.id}\t#{link}"
      puts
      puts "Title: %-60s" % [issue.title.to_s[0..59]]
      puts "Body:  %-60s" % issue.body.to_s[0..59]
      puts "^" * 80
    end

    def dump_issue_comment(comment)
      user = comment.try(:user)
      puts "v" * 85
      puts dump_user_info(user)
      puts "-" * 85
      # Unfortunately, we have some IssueComments in the system where Issue is
      # nil (254158, e.g.)
      if comment.issue.nil?
        puts "IC #{comment.id} - couldn't retrieve associated Issue #{comment.issue_id}"
      elsif comment.issue.repository.nil?
        puts "IC #{comment.id} - couldn't retrieve associated Issue #{comment.issue_id}'s Repo #{comment.issue.repository_id}"
      else
        puts "IC #{comment.id} from Issue #{comment.issue.try(:id)} - #{comment.issue.try(:url)}"
      end
      puts "*" * 70
      puts comment.body
      puts "^" * 70
    end

    def tail_commit_comments(options = nil)
      options ||= {}
      old_comment  = options[:comment] || CommitComment.last
      delay        = options[:delay] || 2
      delay_method = options[:delay_method]
      quiet        = options[:quiet]
      show_spammy  = options[:show_spammy]
      base = show_spammy ? CommitComment : CommitComment.not_spammy
      base = base.joins(:user)

      loop do
        new_comment = base.where(["commit_comments.id > ?", old_comment.id]).includes(:user).first
        if new_comment
          old_comment = new_comment
          next if new_comment.user.hammy?

          dump_commit_comment new_comment unless quiet

          if block_given?
            puts unless quiet
            yield new_comment
            puts unless quiet
          end
        end
        if delay_method.is_a? Proc
          if new_comment
            gap = CommitComment.last.id - new_comment.id
          else
            gap = 0
          end

          delay = delay_method.call(gap)
        end
        sleep delay
      end
    end

    def dump_commit_comment(comment)
      user = comment.try(:user)
      puts "v" * 70
      puts dump_user_info(user)
      puts "-" * 70
      # Unfortunately, we may have CommitComments in the system with a nil Repo
      if comment.repository
        puts "CC #{comment.id} from Repo #{comment.repository.nwo} - #{comment.permalink}"
      else
        puts "CC #{comment.id} (which has no associated Repo) now"
      end
      puts "*" * 70
      puts comment.body
      puts "^" * 70
    end

    def tail_commit_mentions(options = nil)
      options ||= {}
      old_mention = options[:commit_mention] || CommitMention.last
      delay       = options[:delay] || 2
      base        = CommitMention.joins(:repository)

      loop do
        new_mention = base.where(["commit_mentions.id > ?", old_mention.id]).first

        if new_mention
          old_mention = new_mention
          puts "Mention #{new_mention.id} on #{new_mention.created_at}"
          yield new_mention if block_given?
        end
        sleep delay
      end
    end

    ######################################################################
    ######
    ##
    ##  issue_spammer and gist_spammer hunting section
    ##
    ######
    ######################################################################
    # github/gist -> revision_view.rb
    def gist_commit_time(revision)
      case time = revision["author"][2]
      when String
        Time.iso8601(time)
      when Array
        GitRPC::Util.unixtime_to_time(time, suppress_offset_errors: gist.feature_flag_enabled?(:suppress_offset_errors_for_commit_date, default: true))
      else
        raise ArgumentError, "time expected to be string or array, not #{time.inspect}"
      end
    end

    # github/gist -> gist.rb   ~ lines 300-350
    def get_gist_revisions(gist)
      revision_shas = gist.rpc.list_revision_history(gist.sha)
      gist.read_objects(revision_shas, :commit)
    end

    def gist_revisions_delay(revisions_or_gist)
      if revisions_or_gist.is_a? Gist
        revisions = get_gist_revisions(revisions_or_gist)
      else
        revisions = revisions_or_gist
      end
      return -1 unless revisions.count > 1
      time_newer = gist_commit_time(revisions.first)
      time_older = gist_commit_time(revisions.last)
      time_newer - time_older
    end

    MEGAGISTSPAMMER_INTERVAL = 90
    def megaspammer_gist(gist)
      return false unless file = gist.files.first
      return false unless file.data.length < 16000
      revisions = get_gist_revisions(gist)
      return false unless revisions.count > 1
      return false unless gist_revisions_delay(revisions) < MEGAGISTSPAMMER_INTERVAL

      # I haven't worked out whether I care about the difference between these two
      is_spam = (file.data =~ /(< [a-gi-z][a-z\.]* \d+ > [^<]+ < \/ [a-gi-z][a-z\.]* \d+ >) {2,}/xi)
      # <t1>blah</t1>...   or <gist1.gist>blah</gist2.gist>... but not <h1>blah</h1>
      is_spam ||= (file.data =~ /(?:<( [a-gi-z] [a-z\.]* \d+ )> [^<]* <\/\1>){3,}/ixm)
      # <X!!.X!!6>Ga</X!!.X!!6><X!!.X!!11>latas</X!!.X!!11><X!!.X!!12>
      is_spam ||= (file.data =~ /<([a-z])!!\.?(\1|\d)/ixm)
      is_spam ||= (file.data =~ /([a-z])!!\.?(\1)!!/ixm)
      is_spam ||= (file.data =~ /!!([a-z])!!.+!!(\1)!!/ixm)
      # <Z?!>P<Z?!><Z?.>s<Z!&>
      is_spam ||= (file.data =~ /<([a-z]+[^a-z0-9]{1,4}[A-Za-z]*)>.*<(\1)>.+<(\1)>/ixm)
      # <F!F10>x</F!F10>
      is_spam ||= (file.data =~ /<([a-z][^a-z0-9][a-z]\d+)>.+<\/\1>/im)
      is_spam ||= (file.data =~ /Gist.Gistscript-follow-button/im)
      is_spam ||= (file.data =~ /www\.linux-es\.org\/node/im)
      is_spam
    end

    def has_last_ip_pattern?(user)
      SpamPattern.matches_for(user).any? { |sp| sp.attribute_name == "last_ip" }
    end

    def build_issue_query(keyword, max_age, page = 1)
      phrase = keyword + " created:>=" + max_age.strftime("%Y-%m-%d")
      Search::Queries::IssueQuery.new(
        phrase: phrase,
        page: page,
        per_page: 100,
        context: "#{self.class.name&.demodulize.underscore}-#{__method__}",
      )
    end

    def find_issue_spammers(keywords, number_of_spammers_per_query = 30, max_age = 7.days.ago)
      spammers = []

      keywords.each do |keyword|
        collect = true
        page = 1
        hits = []

        while collect
          results = build_issue_query(keyword, max_age, page).execute
          hits.concat results.results

          if results.next_page.present?
            page = results.next_page
          else
            collect = false
          end
        end

        # Heuristics to help reduce false positives:
        # * filter out Issues owned by whitelisted users

        results = hits.select { |result| result["_model"].user.can_be_flagged? }
        spammers.concat results.last(number_of_spammers_per_query).map { |result| result["_model"].user.login }.uniq
      end

      spammers.uniq
    end

    def extra_protection_queue_key
      "extra_protection_spam"
    end

    def extra_protection_queue
      @epq ||= Spam::Queue.new(extra_protection_queue_key, "Users receiving extra spam protection")
    end

    def extra_protect_user(target)
      target = target.login if target.is_a? User
      extra_protection_queue.push target
    end

    def is_extra_protected?(target)
      target = target.login if target.is_a? User
      extra_protection_queue.is_member? target
    end

    def extra_protection_repo_queue_key
      "extra_protection_repo_spam"
    end

    def extra_protection_repo_queue
      @eprq ||= Spam::Queue.new(extra_protection_repo_queue_key, "Repos receiving extra spam protection")
    end

    def extra_protect_repo(target)
      target = target.nwo if target.is_a? Repository
      extra_protection_repo_queue.push target
    end

    def is_extra_protected_repo?(target)
      target = target.nwo if target.is_a? Repository
      extra_protection_repo_queue.is_member? target
    end

    def harden_spammy_reason(user)
      if user.spammy
        user.mark_as_spammy hard_flag: true
      else
        puts "User is not currently flagged as spammy"
      end
    end

    MUNCH_ISSUES_NEXT_ISSUE_ID_KEY = "munch_issues_next_issue_id_key"

    def get_next_issue_to_munch
      next_issue_id_to_munch = Spam::Kv.store.get(MUNCH_ISSUES_NEXT_ISSUE_ID_KEY).value!
      if next_issue_id_to_munch
        Issue.where("id >= ?", next_issue_id_to_munch).first
      else
        Issue.last
      end
    end

    def munch_issues_delay
      0.25
    end

    def munch_issues(start_issue = get_next_issue_to_munch)
      Spam::Origin.console_origin = :console_munch_issues
      progress_marker = 0
      tail_issues(issue: start_issue,
                  delay_method: lambda { |gap| variable_delay_method(gap, min: munch_issues_delay) },
                  quiet: true,
                  ) do |issue|
        last_id = Issue.last.id
        gap = last_id - issue.id
        if gap > 5
          print red("Gap is #{gap} (#{issue.id} => #{last_id}) (delay: %.02f)\r" %
                   variable_delay_method(gap, min: munch_issues_delay))
        end

        # Periodically save our progress
        if (progress_marker += 1) > 100
          progress_marker = 0
          save_progress(MUNCH_ISSUES_NEXT_ISSUE_ID_KEY, issue.id - 1)
        end

        next unless user = issue.user
        next unless user.can_be_flagged?

        next if %w[Flashyller PuffGree SporksRule MazorLajer AlmostPrecise
          LungingDuckSquat LobsterStrikesBack TheHolyHamster WackyChihuahua
          SplendidDorito DarthCorgious DetectiveJakePeralta BoatSnack
          TheOceanMaster TerryLovesYogurt FettyConfetti TempurpedicPilsner
          HamsterOnRails LobsterOnRails LeggyMyEggy nainardev
          tobedeleted1234].include? user.login

        puts if gap > 5

        dump_issue issue

        velocity = iph_while_active(user)
        if velocity > 10
          if transliterate(user.issues.last.body) =~ /\.-?c-?0-?m/i
            qf user, "Issue mega-spammer caught via transliterate"
            notify(":lock_with_ink_pen: Caught Mega-spammer with #{user.login} using transliterate")
          elsif user.issues.last.body =~ /。C０M/
            qf user, "Issue mega-spammer"
            notify("Caught Mega-spammer at it again with #{user.login}")
          end
          unless has_last_ip_pattern? user
            puts "Pushing #{user.login} onto PSQ (velocity: #{velocity})"
            q.push user.login
          end
        end
      end
    ensure
      Spam::Origin.console_origin = :console
    end

    MUNCH_COMMIT_COMMENTS_NEXT_COMMIT_COMMENT_ID_KEY = "munch_commit_comments_next_commit_comment_id_key"

    def get_next_commit_comment_to_munch
      next_commit_comment_id_to_munch = Spam::Kv.store.get(MUNCH_COMMIT_COMMENTS_NEXT_COMMIT_COMMENT_ID_KEY).value!
      if next_commit_comment_id_to_munch
        CommitComment.where("id >= ?", next_commit_comment_id_to_munch).first
      else
        CommitComment.last
      end
    end

    def munch_commit_comments(start_comment = get_next_commit_comment_to_munch)
      Spam::Origin.console_origin = :console_munch_commit_comments
      progress_marker = 0
      @arthurvr ||= dat("arthurvr")
      tail_commit_comments(comment: start_comment,
                           quiet: true,
                           delay_method: lambda { |gap| variable_delay_method(gap, min: 1) }) do |comment|
        last_id = CommitComment.last.id
        gap = last_id - comment.id
        if gap > 5
          puts red("Gap is #{gap} (#{comment.id} => #{last_id}) (delay: %.02f)" %
                   variable_delay_method(gap, min: 1))
        end

        # Periodically save our progress
        if (progress_marker += 1) > 100
          progress_marker = 0
          save_progress(MUNCH_COMMIT_COMMENTS_NEXT_COMMIT_COMMENT_ID_KEY, comment.id - 1)
          dump_commit_comment comment
        end

        next unless user = comment.user
        next unless user.can_be_flagged?

        if user.created_at > 24.hours.ago
          if comment.body =~ /a+-?r+-?t+-?h+-?u+-?r+|mdo/i
            qf user, "CommitComment body spam: #{comment.id} - #{comment.permalink} (via munch_commit_comments w/arthur+mdo check)"
            notify(":rage: Suspected harasser #{user.login} on #{comment.permalink} using munch_commit_comments and arthur+mdo check. Elapsed time: %.02f seconds" % (Time.now - comment.created_at))
            q.push user
            next
          else
            repo = comment.repository
            if repo && (repo.adminable_by?(@arthurvr) || @arthurvr.watching_repo?(repo))
              qf user, "CommitComment spam: #{comment.id} - #{comment.permalink} (via munch_commit_comments w/arthurvr check)"
              notify(":rage: Suspected harasser #{user.login} on #{comment.permalink} using munch_commit_comments and arthurvr check. Elapsed time: %.02f seconds" % (Time.now - comment.created_at))
              q.push user
              next
            end
          end
        end
      end
    ensure
      Spam::Origin.console_origin = :console
    end

    def reddit_spammer(gist)
      return false unless gist && gist.user
      return false unless gist.files.first.data.length < GitHub::SpamChecker::GIST_MAX_FILE_DATA
      gist.created_at < (gist.user.created_at + 2.days) &&
        gist.files.first.data =~ /reddit\.com\/[a-z0-9]{6}(?:\/|\z)/im
    end

    def calendar_spammer(gist)
      return false unless gist && gist.user
      return false unless gist.files.first.data.length < GitHub::SpamChecker::GIST_MAX_FILE_DATA
      gist.files.first.data =~ /printable.*calendar/im
    end

    def clipart_spammer(gist)
      return false unless gist && gist.user
      return false unless gist.files.first.data.length < GitHub::SpamChecker::GIST_MAX_FILE_DATA
      gist.files.first.data =~ /clip\s*art/im
    end

    def is_sports_gist(gist)
      return false unless gist.files.first.try(:data).present?
      return false unless gist.files.first.data.length < GitHub::SpamChecker::GIST_MAX_FILE_DATA
      specimen = Spam::Specimen.new(gist.files.first.data)
      answer = specimen.text =~ /(houston|rockets)/i &&
        specimen.text =~ /(golden|warriors)/i &&
        specimen.text =~ /(live|streaming)/i
      answer ||= specimen.text =~ /maci/i &&
        specimen.text =~ /canli/i &&
        specimen.text =~ /izle/i
      answer ||= specimen.text =~ /galatasaray/i &&
        specimen.text =~ /besiktas/i
      answer
    end

    def red_swarm_rising(gist)
      return false unless gist && gist.user
      return false unless gist.files.first.data.length < GitHub::SpamChecker::GIST_MAX_FILE_DATA
      return false unless gist.created_at < (gist.user.created_at + 5.minutes)
      data = gist.files.first.data
      anon_gist_regexp = Regexp.union(
        /cpatds2\.ru/,
        /fastnodesus\.tk/,
        /скачать/im,
        /no-ip\..+\/download\?file/,
        /is.gd\/.+Download/,
        /href=\"\s*\" target.{10,40}>Download/,
      )
      data =~ anon_gist_regexp
    end

    def save_progress(key, id)
      return unless key
      Spam::Kv.store.set(key, id.to_s)
    end

    MUNCH_GISTS_NEXT_GIST_ID_KEY = "munch_gists_next_gist_id_key"

    def get_next_gist_to_munch
      next_gist_id_to_munch = Spam::Kv.store.get(MUNCH_GISTS_NEXT_GIST_ID_KEY).value!
      if next_gist_id_to_munch
        Gist.where("id >= ?", next_gist_id_to_munch).first
      else
        Gist.last
      end
    end

    def grab_gist_data_with_limit(gist)
      return nil if gist.files.empty?
      gist.files.first.data[0..GitHub::SpamChecker::GIST_MAX_FILE_DATA]
    end

    def gist_classification(gist, debug: false, max_files: 5)
      utf8_files = gist.files.select { |f| f.encoding == "UTF-8" }
      files = Gist.limit_files(utf8_files, max_files)
      data = files.map { |f| { content_id: f.info["oid"], content: f.name + ": " + f.data[0..2047] } }
      return "" if data.empty?

      payload = { data: data }
      r = faradapter.post("/predict/gist", payload.to_json)
      if r.status == 200
        d = JSON::parse(r.body)
        if debug
          d.dig("results")
        else
          highest = d.dig("results").max_by { |r| r.dig("probability") }
          highest.dig("threat_level")
        end
      else
        debug ? r : false
      end
    end

    def munch_gists(start_gist = get_next_gist_to_munch, end_gist_id = nil)
      Spam::Origin.console_origin = :console_munch_gists
      progress_marker = 0
      last_id = end_gist_id if end_gist_id
      tail_gists(gist: start_gist,
                 delay_method: lambda { |gap| variable_delay_method(gap) },
                 quiet: true) do |gist|
        if end_gist_id
          break if gist.id > end_gist_id
        else
          last_id = Gist.last.id
        end
        gap = last_id - gist.id
        if gap > 10
          print red("Gap is #{gap} (#{gist.id} => #{last_id}) (delay: %.02f)\r" %
                   variable_delay_method(gap))
        end

        # Periodically save our progress
        if (progress_marker += 1) > 100
          progress_marker = 0
          save_progress(MUNCH_GISTS_NEXT_GIST_ID_KEY, gist.id - 1)
        end

        gist_age = Time.now - gist.created_at
        if gist_age < MEGAGISTSPAMMER_INTERVAL
          puts blue("\nSleeping #{MEGAGISTSPAMMER_INTERVAL - gist_age} seconds to let spammers catch up")
          sleep(MEGAGISTSPAMMER_INTERVAL - gist_age)
        end
        next unless user = gist.user
        next if user.spammy? || !user.can_be_flagged?
        next if user.created_at < 6.months.ago
        next unless gist.files.present?

        puts if gap > 10

        puts "\n" + "=" * 75
        gist_snip gist
        puts "Checking Gist #{gist.id} - #{gist.url}"

        begin
          if gist_classification(gist) == "CRITICAL"
            puts purple("WANT to flag #{user} as spammer because Gist classifier says CRITICAL")
            #          qf user, "Gist spam: #{gist.id} - #{gist.permalink} (via munch_gists with content-based-classifier)"
            notify(":imp: Pushing possible Gist spammer #{user.login} on Gist ID #{gist.id} using munch_gists and content-based-classifer. Elapsed time: %.02f seconds" % [(Time.now - gist.created_at)])
            q.push user.login
          end
        rescue Faraday::ConnectionFailed => e
          puts "#{invert_yellow('RESCUED:')} in munch_gists: #{e}"
        end

        if calendar_spammer(gist)
          puts purple("Queuing #{user} as likely calendar spammer for Gist %d (%s)" % [gist.id, gist.url])
          notify("Suspected calendar Gist spammer %s on Gist %s (%s) using munch_gists. Elapsed time: %.02f seconds" % [user.login, gist.id, gist.url, (Time.now - gist.created_at)])
          q.push user.login
        end

        if clipart_spammer(gist)
          puts purple("Queuing #{user} as likely clipart spammer for Gist %d (%s)" % [gist.id, gist.url])
          notify("Suspected clipart Gist spammer %s on Gist %s (%s) using munch_gists. Elapsed time: %.02f seconds" % [user.login, gist.id, gist.url, (Time.now - gist.created_at)])
          q.push user.login
        end

        if reddit_spammer(gist)
          puts purple("Queuing #{user} as likely reddit spammer for Gist %d (%s)" % [gist.id, gist.url])
          notify("Suspected reddit Gist spammer %s on Gist %s (%s) using munch_gists. Elapsed time: %.02f seconds" % [user.login, gist.id, gist.url, (Time.now - gist.created_at)])
          q.push user.login
        end

        if megaspammer_gist(gist)
          #          qf user, "Gist spam - streaming sports megaspammers again (formerly dT)"
          unless has_last_ip_pattern? user
            puts purple("Pushing #{user.login} onto PSQ (steenking Gist spammer) - #{gist.url}")
            q.push user.login
          end
          next  # Caught this one; move on
        end

        if is_sports_gist(gist)
          qf user, "Gist spam - streaming sports"
          unless has_last_ip_pattern? user
            puts "Pushing #{user.login} onto PSQ (steenking sports Gist spammer) - #{gist.url}"
            q.push user.login
          end
          next  # Caught this one; move on
        end

        if red_swarm_rising(gist)
          qf user, "Gist spam storm from Russia with love"
          unless has_last_ip_pattern? user
            puts "Pushing #{user.login} onto PSQ (the Russians are coming) - #{gist.url}"
            q.push user.login
          end
          next  # Caught this one; move on
        end

        if user.email =~ /@[^.]+$/
          if (user.gists.minimum(:created_at) - user.created_at) < 600
            #            qf user, "Gist spam - streaming sports megaspammers (formerly dT) caught by email + Gist creation interval"
            puts purple("Pushing #{user.login} onto PSQ. Suspected streaming sports spammer, based on email + Gist creation interval - #{gist.url}")
            q.push user.login
          end
        end

        velocity = gph_while_active(user)
        if velocity > 15 && user.gists.count > 4
          #          qf user, "Gist spam - caught by Cthulhu script for too many Gists too quickly after creation"
          unless has_last_ip_pattern? user
            puts "Pushing #{user.login} onto PSQ (velocity: #{velocity})"
            q.push user.login
          end
        end
      end  # tail_gists
    ensure
      Spam::Origin.console_origin = :console
    end

    def queue_probable_little_lamb(user, context = nil)
      return unless llq = SpamQueue.find_by_name("probable_little_lambs")
      llq.push user: user, additional_context: context
    end

    MUNCH_GIST_COMMENTS_NEXT_GIST_COMMENT_ID_KEY = "munch_gist_comments_next_gist_comment_id_key"

    def get_next_gist_comment_to_munch
      next_gist_comment_id_to_munch = Spam::Kv.store.get(MUNCH_GIST_COMMENTS_NEXT_GIST_COMMENT_ID_KEY).value!
      # rubocop:enable GitHub/DoNotUseGlobalKv
      if next_gist_comment_id_to_munch
        GistComment.where("id >= ?", next_gist_comment_id_to_munch).first
      else
        GistComment.last
      end
    end

    def mgc_delay
      0.35
    end

    def munch_gist_comments(start_comment = get_next_gist_comment_to_munch)
      Spam::Origin.console_origin = :console_munch_gist_comments
      progress_marker = 0
      gc_patterns = Spam.get_current_patterns("gist_comment").map { |pattern| Regexp.new(pattern) }
      tail_gist_comments(comment: start_comment,
                         delay_method: lambda { |gap| variable_delay_method(gap, min: mgc_delay) },
                         skip_private: true,
                         quiet: true) do |comment|
        last_id = GistComment.last.id

        # Periodically save our progress
        if (progress_marker += 1) > 100
          progress_marker = 0
          save_progress(MUNCH_GIST_COMMENTS_NEXT_GIST_COMMENT_ID_KEY, comment.id - 1)
        end

        putc(".")
        next unless comment.body.present?
        next unless user = comment.user
        next unless user.can_be_flagged?
        puts

        gap = last_id - comment.id
        if gap > 5
          puts red("Gap is #{gap} (#{comment.id} => #{last_id}) (delay: %.02f)" %
                   variable_delay_method(gap, min: mgc_delay)) +
               blue("\t\t%s" % comment.created_at.in_time_zone("Central Time (US & Canada)").strftime("%Y-%m-%d %H:%M:%S %Z"))
        end

        # Dump it here since we're shutting up tail_gist_comments
        dump_gist_comment comment

        gc_patterns.each do |regex|
          if comment.body =~ regex
            qf user, "GistComment spam: #{comment.id} - #{comment.gist.permalink} (via munch_gist_comments with regex #{regex})"
            notify(":imp: Caught GistComment spammer #{user.login} on #{comment.id} on #{comment.gist.permalink} using munch_gist_comments and regex #{regex}. Elapsed time: %.02f seconds" % (Time.now - comment.created_at))
            break
          end
        end
        next if user.spammy? # bounce if we've already caught them

        puts "*" * 70
        puts
      end
    ensure
      Spam::Origin.console_origin = :console
    end

    def the_one_before_this(user, options = {})
      options[:how_many] = 1
      the_last_few_before_this(user, options).last
    end

    def the_last_few_before_this(user, options = nil)
      options ||= {}
      how_many    = (options[:how_many] || 5).to_i
      days_ago    = (options[:days_ago] || 7).to_i
      c_class     = (options[:c_class] || options[:wide])
      verbose     = options[:verbose].to_i

      since = user.created_at - days_ago.days

      if c_class && user.try(:last_ip).present?
        user.last_ip =~ /\d+\.\d+\.\d+/
        ip = $~[0] + ".%"
        base = User.from("users FORCE INDEX(index_users_on_last_ip)").where("last_ip like ?", ip)
      else
        base = User.by_ip(user.last_ip)
      end

      base.where("id < ?", user.id).where("created_at > ?", since).last(how_many)
    end

    def the_next_few_after_this(user, options = nil)
      options ||= {}
      how_many    = (options[:how_many] || 5).to_i
      days_later  = (options[:days_later] || 7).to_i
      c_class     = (options[:c_class] || options[:wide])
      verbose     = options[:verbose].to_i

      after = user.created_at + days_later.days

      if c_class && user.try(:last_ip).present?
        user.last_ip =~ /\d+\.\d+\.\d+/
        ip = $~[0] + ".%"
        base = User.from("users FORCE INDEX(index_users_on_last_ip)").where("last_ip like ?", ip)
      else
        base = User.by_ip(user.last_ip)
      end

      base.where("id > #{user.id}").where("created_at < ?", after).first(how_many)
    end

    def audit_log_results_include_both_payment_events(results)
      actions = results.collect { |t| t["action"] }
      actions.include?("payment_method.create") &&
        actions.include?("payment_method.remove")
    end

    def audit_log_payment_events(user, verbose = nil)
      @results_cache ||= {}
      @results_cache_key_queue ||= []
      if @results_cache[user.login]
        puts green("In audit_log_payment_events: Using cached results for #{user.login}") if verbose
        results = @results_cache[user.login]
      else
        puts "In audit_log_payment_events: Looking up audit results for #{user.login}" if verbose
        phrase = "action:payment_method.create user:#{user.login}"
        if GitHub.driftwood_ade_queries_enabled?
          phrase = "webevents | where action == 'payment_method.create' and user_id == '#{user.id}'"
        end
        results = Audit::Driftwood::Query.new_stafftools_query({ phrase: phrase, current_user: user }).execute.results
        @results_cache[user.login] = results
        @results_cache_key_queue << user.login
        # Keep it trimmed
        if @results_cache_key_queue.size > 1000
          @results_cache.delete @results_cache_key_queue.shift
        end
      end
      results
    end

    def is_guzzle_agent?(user)
      return false unless user.is_a? User
      return false unless user.user?
      last_session = user.sessions.last
      if last_session.nil?
        if user.login =~ /-/
          notify(":fish: User #{user} has a hyphenated login but no session")
        end
        return false
      end

      last_agent = last_session.user_agent
      last_agent =~ /Guzzle/ && last_agent =~ /curl/ && last_agent =~ /PHP/
    end

    # Check for the login-login spammer
    def examine_for_login_login_spammer(user)
      spammer_parts = []
      missing_part = nil

      login_parts = user.login.split("-").reject { |t| t.length < 3 }

      if login_parts.count == 2
        # Neither of the login parts ever appear in the email address of our
        # login-login spammer, but frequently do for false positives on just
        # the login parts.
        if login_parts.none? { |part| user.email =~ /#{part}/i }
          spammer_parts = login_parts.select { |t| login_login_spammer_part? t }
          missing_part = (login_parts - spammer_parts).first
        end
      end

      [spammer_parts, missing_part]
    end

    def report_grouped_by_ip(collection)
      ips = Hash.new(0)
      collection.each do |user|
        ips[user.last_ip] += 1
      end
      ips.keys.sort_by { |t| t.split(".").last.to_i }.each { |k| puts "#{k}\t#{ips[k]}" }
      nil
    end

    def qq_flood_account(user)
      if user.login =~ /\A([a-z]{5})\d{3}\z/
        login_part = $~[1]
        if user.email =~ /\A([a-z]{5})\d{3}@qq.com\z/
          email_part = $~[1]
          login_part != email_part  # return true if they're different
        end
      end
    end

    def gmail_flood_account(user)
      user.login.length > 14 &&
        user.login =~ /\A([a-z]+\d{10,10})\d+\z/ &&
        user.email.to_s.split("@").first =~ /\A#{$1}\d+\z/
    end

    def gmail_flood_account_redux_login_and_email(user)
      mailbox = user.email.to_s.split("@").first
      user.login.length > 5 &&
        mailbox != user.login &&
        user.email.to_s.end_with?("@gmail.com") &&
        GitHub::Levenshtein.similarity(user.login, mailbox) < 0.30
    end

    def gmail_flood_account_context(user)
      the_last_few_before_this(user, how_many: 5, days_ago: 30, wide: true).any? do |t|
        t.suspended? ||
          t.spammy_reason.to_s =~ /\[gmail_flood_account\]/ ||
          gmail_account_flood_audit_payment_pattern(t) ||
          gmail_account_flood_audit_credit_card_pattern(t)
      end
    end

    def gmail_account_flood_audit_payment_pattern(user, verbose = false)
      results = audit_log_payment_events(user)

      return false unless audit_log_results_include_both_payment_events(results)

      first_pmt_interval = (results.collect { |t| t["created_at"] }.min - user.created_at.to_i * 1000) / 1000.0
      pmt_event_gap = results_gap(results.first, results.last) / 1000.0
      if (first_pmt_interval < 45) && (pmt_event_gap < 15)
        puts "User: #{user.login} - fpi: #{first_pmt_interval}  peg: #{pmt_event_gap}" if verbose
        true
      end
    end

    def gmail_account_flood_audit_credit_card_pattern(user, verbose = false)
      results = audit_log_payment_events(user)
      return false if results.empty?

      first_cc_interval = (results.collect { |t| t["created_at"] }.min - user.created_at.to_i * 1000) / 1000.0
      if first_cc_interval < 10
        puts "User: #{user.login} - added CC in #{first_cc_interval} seconds" if verbose
        true
      end
    end

    def gmail_flood_account_cinco(user, verbose = false)
      return false unless gmail_flood_account_cinco_login_and_email(user)
      return true if gmail_flood_account_context(user)
      # Now check if the last one shares our login/email pattern
      last_one = the_one_before_this(user, how_many: 5, days_ago: 30, wide: true)
      last_one && gmail_flood_account_cinco_login_and_email(last_one)
    end

    def gmail_flood_account_cinco_login_and_email(user)
      return false unless user.email.present? && user.email =~ /@gmail.com/
      mailbox = user.email.to_s.split("@").first
      partial_match = (mailbox =~ /\A([a-z]+)[a-z]{2,2}\d{4,4}\z/) &&
                      (user.login =~ /\A#{$1}[a-z]+\z/)
      # This method shouldn't return true if the entire non-numeric part of
      # the mailbox is present anywhere in the login.
      not_too_much = (mailbox =~ /\A([a-z]+)\d{4,4}\z/) &&
                     (user.login !~ /#{$1}/)
      partial_match && not_too_much
    end

    def gmail_flood_account_redux(user)
      gmail_flood_account_redux_login_and_email(user) &&
        gmail_flood_account_context(user)
    end

    def gmail_flood_account_tres_login_and_email(user)
      user.login =~ /\A([a-z]{4,11})\d{5,6}\z/ &&
        user.email.to_s.split("@").first =~ /#{$1}/
    end

    def gmail_flood_account_tres(user)
      gmail_flood_account_tres_login_and_email(user) &&
        gmail_flood_account_context(user)
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

    def get_ips(users)
      Array(users).collect { |t| t.try(:last_ip) }.compact.uniq
    end

    def add_entry(sd, value, context = nil)
      if entry = sd.entries.find_by_value(value)
        puts "SpamDatasource %d already had an entry for '%s': %d. Not adding this one." % [sd.id, value, entry.id]
      else
        entry = sd.entries.create value: value, additional_context: context
        puts "Entry %d added. SpamDatasource %d now has %d entries." % [entry.id, sd.id, sd.entries.count]
      end
    end

    def unfollow_bulk(main_user, users_to_unfollow)
      users_to_unfollow.each do |user|
        user.followers_count!
        main_user.following.delete(user)
      end

      main_user.following_count!
    end

    def audit_event_dump(user)
      pe = audit_log_payment_events user
      created = user.created_at.to_i * 1000.0
      pe.sort_by { |t| t["created_at"] }.each do |event|
        pe_time = event["created_at"].to_i
        delay = (pe_time - created) / 1000.0
        puts "%8.02fs - %s" % [delay, event["action"]]
      end
      nil
    end

    def gflood(these)
      changed = 0
      total = 0
      Array(these).each do |t|
        total += 1
        next if t.spammy_reason =~ /\[gmail_flood_account\]/
        changed += 1
        new_spammy_reason = GitHub::SpamChecker.add_to_message_with_limit(t.spammy_reason, "[gmail_flood_account]")
        t.update_attribute :spammy_reason, new_spammy_reason
      end
      puts "Changed #{changed} of #{total}"
    end

    def get_mailbox(user)
      return "" unless user.is_a? User
      user.email.to_s.split("@").first.to_s
    end

    # Return delay from options[:min] to options[:max] seconds,
    # depending on how big the gap is.
    def variable_delay_method(gap, options = nil)
      options ||= {}
      max = options[:max] || 5
      min = options[:min] || 0.3
      if gap.to_i <= 0
        value = max
      else
        calc = max - Math.log(gap)
        value = [[max, calc].min, min].max
      end
      value
    end

    def munch_commit_mentions(start_mention = CommitMention.last, end_mention_id = nil)
      Spam::Origin.console_origin = :console_munch_commit_mentions
      last_id = end_mention_id if end_mention_id
      tail_commit_mentions(commit_mention: start_mention, delay: 1) do |mention|
        if end_mention_id
          break if mention.id > end_mention_id
        else
          last_id = CommitMention.last.id
        end
        gap = last_id - mention.id
        if gap > 20
          puts red("Gap is #{gap} (#{mention.id} => #{last_id})")
        end

        next unless user = mention.user
        next if user.spammy? || !user.can_be_flagged?
        next if user.created_at < 3.days.ago

        begin
          commit = mention.commit
          puts "Checking CommitMention #{mention.id} - #{commit.permalink}"

          if commit.message.present?
            if commit.message =~ /@arthurvr/
              qf mention.user, "CommitMention spam: #{mention.id} - #{commit.permalink} (via munch_commit_mentions w/arthurvr check)"
              notify(":rage: Suspected harasser #{mention.user.login} on #{commit.permalink} using munch_commit_mentions and arthurvr check. Elapsed time: %.02f seconds" % (Time.now - mention.created_at))
              q.push mention.user
              break
            end
          end
        rescue GitRPC::Error => e
          puts "Couldn't get Commit from CommitMention #{mention.id}; skipping. Msg was [#{e}]"
          next
        end
      end
    ensure
      Spam::Origin.console_origin = :console
    end

    def sample_blob(repo, filename)
      filenames = GitHub::SpamChecker.get_repo_filenames(repo, false)
      return "" unless filenames.include? filename

      blob = repo.tree_entry(repo.default_oid, filename, limit: GitHub::SpamChecker::MAX_BLOB_SIZE_TO_CHECK)
      blob.data
    end

    def russian_affair_repo(repo, verbose = false)
      filenames = GitHub::SpamChecker.get_repo_filenames(repo, verbose)
      return false unless filenames == ["index.html"]

      blob = repo.tree_entry(repo.default_oid, "index.html", limit: GitHub::SpamChecker::MAX_BLOB_SIZE_TO_CHECK)
      blob.data =~ /window.location.href/
    end

    def munch_repos_delay
      0.25
    end

    def munch_repos(start_repo = Repository.last)
      Spam::Origin.console_origin = :console_munch_repos
      tail_repos(repo: start_repo, delay: munch_repos_delay) do |repo|
        last_id = Repository.last.id
        gap = last_id - repo.id
        if gap > 5
          puts red("Gap is #{gap} (#{repo.id} => #{last_id})")
        end

        next unless user = repo.user
        next unless user.can_be_flagged?

        # This lets us go back and apply this to older repos which were
        # created right after their creating spammer account was, even if
        # those accounts and repos are *now* well over 24 hours old.
        if (repo.created_at - user.created_at) < 24.hours
          if russian_affair_repo(repo)
            qf user, "Repo 'Russian affair' spam: #{repo.id} - #{repo.permalink} (via munch_repos w/russian_affair_repo check)"
            notify(":clock2: Repo 'Russian affair' spammer #{user.login} on #{repo.permalink} using munch_repos and russian_affair_repo check. Elapsed time: %.02f seconds" % (Time.now - repo.created_at))
            puts blue("Caught #{user} for 'tech support' spam attempt on repo #{repo.nwo}")
            q.push user
            next
          end
        end

        if user.created_at > 24.hours.ago
          if repo.name =~ /astrolog/ && repo.name =~ /-/
            qf user, "Repo spam: #{repo.id} - #{repo.permalink} (via munch_repos w/astrology check)"
            notify(":clock1: Suspected spammer #{user.login} on #{repo.permalink} using munch_repos and astrology check. Elapsed time: %.02f seconds" % (Time.now - repo.created_at))
            puts blue("Nailing #{user} for not foreseeing the future well enough on #{repo.nwo}")
            q.push user
            next
          end
        end    # User is < 24 hours old

      end
    ensure
      Spam::Origin.console_origin = :console
    end

    def tail_emails(options = nil)
      options ||= {}
      old_email    = options[:email] || UserEmail.last
      delay        = options[:delay] || 2
      delay_method = options[:delay_method]
      quiet        = options[:quiet]
      show_spammy  = options[:show_spammy]
      base         = show_spammy ? UserEmail : UserEmail.not_spammy

      loop do
        new_email = base.where(["id > ?", old_email.id]).first
        if new_email
          old_email = new_email
          user = new_email.user
          # We don't really want to see the auto-generated internal emails
          unless quiet || new_email.email == "#{user&.id}+#{user&.login}@users.noreply.github.com"
            puts "#{new_email.id} - #{new_email.email}"
            if user
              puts "#{user.id} - #{user.login} - #{user.created_at}"
            end
            puts "*" * 80
          end
          if block_given?
            yield new_email
            puts unless quiet
          end
        end
        if delay_method.is_a? Proc
          if new_email
            gap = UserEmail.last.id - new_email.id
          else
            gap = 0
          end

          delay = delay_method.call(gap)
        end
        sleep delay
      end
    end

    def tail_repos(options = nil)
      options    ||= {}
      old_repo     = options[:repo] || options[:repository] || Repository.last
      delay        = options[:delay] || 2
      quiet        = options[:quiet]
      show_spammy  = options[:show_spammy]
      skip_private = options[:skip_private]
      base = show_spammy ? Repository : Repository.not_spammy
      base = base.public_scope if skip_private
      base = base.joins(:owner)
      query = " repositories.id > ?"

      loop do
        new_repo = base.where([query, old_repo.id]).first

        if new_repo
          old_repo = new_repo

          unless quiet
            puts green(activity_summary_short(new_repo.user))
            puts repo_summary(new_repo)

            puts
          end
          if block_given?
            yield new_repo
            puts unless quiet
          end
        end
        sleep delay
      end
    end

    ######################################################################
    ######
    ##
    ##  Finito of issue_spammer and gist_spammer hunting section
    ##
    ######
    ######################################################################

    MAX_LINES = 8
    MAX_CHARS = 500

    def snip_text(body)
      body[0..MAX_CHARS].lines.take(MAX_LINES).join
    end

    # These have so many accounts at them (and when put on the list here
    # were not major spam suppliers) that doing spam_and_other_count on
    # them just takes forever.
    def ips_to_skip
      ["208.113.184.5", "94.126.20.153", "208.113.171.60", "72.66.85.18",
       "41.98.2.124", "24.208.88.76", "96.44.189.102", "104.207.129.59",
       "71.198.52.54", "194.226.35.163"
      ]
    end

    def ip_regexps_to_skip
      [/\A183\.240\.196\./]
    end

    def spam_and_other_count(user)
      other_count = 0
      spam_count  = 0
      begin
        if user.last_ip.present? &&
           !ips_to_skip.include?(user.last_ip) &&
           ip_regexps_to_skip.none? { |t| t =~ user.last_ip }
          others = User.by_ip(user.last_ip)
          spam_count  = others.count(&:spammy)
          other_count = others.count
        end
      rescue Organization::NoAdminsError
        puts purple("Whoops! Woulda died here with Org:NoAE for #{user.login}")
      end
      [spam_count, other_count]
    end

    def dump_user_info(user)
      return unless user.is_a? User
      spam_count, other_count = spam_and_other_count(user)
      output = "[%7d] %s %-20s (%3d/%3d) %-15s      %-15s" %
                  [user.id,
                   user_status_summary(user),
                   user.spammy ? red(user.login) : blue(user.login),
                   spam_count, other_count,
                   user.last_ip, user.created_at.to_formatted_s(:db)
                  ]
    end

    def check_tor_node?
      true
    end

    def hours_alive(thing)
      (Time.now - thing.created_at) / 3600
    end

    def gists_per_hour(user)
      user.gists.count / hours_alive(user)
    end

    def issues_per_hour(user)
      user.issues.count / hours_alive(user)
    end

    def velocity_while_active_query
      @velocity_while_active_query ||= <<-'GRAPHQL'
        query($input: String!,
              $record_type: UserAssociatedRecordType!) {
            user(login: $input) {
            stafftoolsInfo {
              associatedRecordCreationVelocity(type: $record_type)
            }
          }
        }
      GRAPHQL
    end

    # Returns the Gists/hour only from first Gist to last Gist created
    def gph_while_active(user)
      variables = { "input" => user.login, "record_type" => "GIST" }
      response = gql velocity_while_active_query, variables: variables
      response.data.dig("user", "stafftoolsInfo",
                               "associatedRecordCreationVelocity") || 0
    end

    def iph_while_active(user)
      variables = { "input" => user.login, "record_type" => "ISSUE" }
      response = gql velocity_while_active_query, variables: variables
      response.data.dig("user", "stafftoolsInfo",
                               "associatedRecordCreationVelocity") || 0
    end

    def gph_threshold
      5
    end

    def target_id
      User.last.id
    end

    def lookup_tor(id, options = {})
      end_id = options[:end_id].to_i
      delay = [options[:delay].to_f, 0.01].max  # delay at least 0.01s between
      quiet = options[:quiet]
      User.where(["id > ?", id.to_i]).find_each do |user|
        if user.last_ip
          result = Spam.is_tor_node?(user.last_ip)
          puts "%d - %15s - %s" % [user.id, user.last_ip, result] unless quiet
        end
        return if (end_id > 0) && (user.id >= end_id)
        sleep delay
      end
    end

    def page_users_header_line(per_page, old_user, min_id, max_id, queue)
      "%d Users: %d - %d\tQ: %d\t\t%s  (%d)" %
        [per_page, min_id, max_id, queue.size,
         old_user.created_at.in_time_zone("Central Time (US & Canada)").strftime("%Y-%m-%d %H:%M:%S %Z"),
         [target_id - max_id, 0].max
        ]
    end

    def page_users_summary_line(user, index = 0)
      email = user.try(:email)
      begin
        spam_count, other_count = spam_and_other_count(user)
        if last_ip = user.last_ip
          if check_tor_node? && Spam.is_tor_node?(last_ip)
            last_ip = purple(last_ip) + " " * (15 - last_ip.length)
          end
        end
        gph = gists_per_hour(user).to_i
        "[%7d] %-15s (%3d/%3d) %2d %s %-20s %4s %s %s" %
          [user.id,
           last_ip,
           spam_count, other_count,
           index,
           user_status_summary(user),
           user.login,
           gph > gph_threshold ? red(gph) : gph,
           has_verified_email?(user) ? green("+") : " ",
           user.spammy ? red(email) : email
          ]
      rescue Faraday::ConnectionFailed, NoMethodError => e
        "#{invert_yellow('RESCUED:')} in page_users_summary_line: #{e}"
      end
    end

    PAGE_USER_LAST_USER_ID_KEY = "page_user_last_user_id_key"

    def page_users(options = nil)
      options ||= {}
      last_user_id_key = Spam::Kv.store.get(PAGE_USER_LAST_USER_ID_KEY).value!
      if options[:user]
        old_user = options[:user]
      elsif last_user_id_key
        old_user = User.where("id >= ?", last_user_id_key).first
      else
        old_user = User.last
      end
      delay       = options[:delay] || 2
      skip_spammy = options[:skip_spammy]
      base        = skip_spammy ? User.not_spammy : User
      per_page    = (options[:per_page] || rows_for_page_users).to_i
      queue       = options[:queue] || Spam.possible_spammer_queue
      verbose     = options[:verbose].to_i

      filter = PagedModelFilter.new(scope: base, sentinel: old_user,
                                    limit: per_page,
                                    progress_key: PAGE_USER_LAST_USER_ID_KEY)
      filter.verbose = verbose

      filter.skip do |user|
        user.email.to_s =~ /\A[a-zA-Z0-9.!\#$%&'*+\/=?^_`{|}~-]+@leeching\.net\z/
      end

      filter.skip do |user|
        user.spammy && qq_flood_account(user)
      end

      filter.skip { |user| Spam.possible_spammer_queue.is_member? user }

      filter.skip do |user|
        # All the users at this IP are already spammy
        spam_count, other_count = spam_and_other_count(user)
        spam_count == other_count
      end

      filter.skip do |user|
        last_ip_sps ||= SpamPattern.where("attribute_name = 'last_ip'")
        # If there's a last_ip SpamPattern that matches this user, skip it
        # unless there are (for some reason) non-spammy Users at the same IP
        # address that are newer than this account.
        if user.spammy && last_ip_sps.any? { |t| t.matches? user }
          puts "Counting later non-spammies" if verbose > 1
          later_non_spammy = User.where(["id > ? AND spammy = 0 AND last_ip = ?", user.id, user.last_ip]).count
          if later_non_spammy == 0
            puts "Skipping #{user.login} at #{user.last_ip} because last_ip and no later non-spammies" if verbose > 0
            true
          end
        end
      end

      # Tired of seeing Tor nodes; just push'em all
      filter.skip do |user|
        puts "Checking #{user.login}'s #{user.last_ip} for Tor node" if verbose > 1
        if check_tor_node? && Spam.is_tor_node?(user.last_ip)
          puts "Tor node (#{user.last_ip}); pushing #{user.login}" if verbose > 0
          Spam.possible_spammer_queue.push user.login
          true
        end
      end
      process_filter(filter, queue)
    end

    def process_filter(filter, queue)
      old_user = filter.sentinel
      loop do
        new_users = filter.advance

        if new_users.empty?
          puts "No matching users with id > #{old_user.id}. Snoozing..."
          sleep 2
          next
        end

        old_user = new_users.first

        max_id = new_users.collect(&:id).max
        min_id = new_users.collect(&:id).min

        puts page_users_header_line(filter.limit, old_user, min_id, max_id, queue)
        users_by_ip = new_users.sort_by { |t| t.last_ip.to_s }
        users_by_ip.each_with_index do |new_user, idx|
          puts page_users_summary_line(new_user, idx)
        end

        f = gets.gsub(/[\.,+]/, " ").strip
        case f
        when /\Aq\s*\z/  # get me outta here, Percy
          return
        when /\Ab\s*\z/  # back a page (or so)
          filter.last_id = [1, min_id - filter.limit - 1].max
        when /\Ag([[:digit:]]+)\z/
          dest = Regexp.last_match(1).to_i
          filter.last_id = [1, dest].max
        when /\Ar\s*\z/  # reload page
          filter.last_id = [1, min_id - 1].max
        when /\A(?:p\s*)?(.+)\s*\z/    # p 13 14 ralph
          indices = Regexp.last_match(1).strip.split(" ")
          candidates = []
          indices.each do |idx|
            idx.strip!
            if idx =~ /\A\d+\z/
              index = idx.to_i
            else
              index = -1
            end
            # If it's a reasonable integer, we assume it's an array index
            if index >= 0 && index <= users_by_ip.size
              candidates << users_by_ip[index].login
            elsif idx.length > 0
              # otherwise if it's a reasonable string let's assume a login
              candidates << idx
            end
          end
          candidates.compact.uniq.each do |candidate|
            puts "Pushing #{candidate}"
            queue.push candidate
          end
        end
      end # while (true)
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

    # Iterate over Users, possibly printing out a summary line for each,
    # and yielding each successive User if a block is given.
    #
    # :user        - User to start on (defaults to most recently-created User)
    # :delay       - Number of seconds to wait before the next User#find
    # :skip_spammy - True if we should skip Users flagged as spammy
    # :quiet       - If true, don't output anything ourselves. Just Iterate
    #                and yield.
    #
    # Returns nothing.
    def tail_users(options = nil)
      options ||= {}
      old_user     = options[:user] || User.last
      delay        = options[:delay] || 2
      delay_method = options[:delay_method]
      quiet        = options[:quiet]
      skip_spammy  = options[:skip_spammy]
      base         = skip_spammy ? User.not_spammy : User

      loop do
        new_user = base.where(["id > ?", old_user.id]).first
        if new_user
          puts page_users_summary_line(new_user) unless quiet
          old_user = new_user
          if block_given?
            puts unless quiet
            yield new_user
            puts unless quiet
          end
        end
        if delay_method.is_a? Proc
          if new_user
            gap = User.last.id - new_user.id
          else
            gap = 0
          end

          delay = delay_method.call(gap)
        end
        sleep delay
      end
    end

    # Dump clusters for this Array of Users sorted by email domain,
    # then email login. Or something close to it.
    def cluster_by_email(u)
      Spam::dump_clusters(
        Spam::build_clusters(
          u.sort_by do |v|
            if v.email
              parts = v.email.split("@")
              "#{parts.last}#{parts.first}"
            else
              ""
            end
          end,
        ),
      )
    end

    # For the User or Array of Users, blacklist all the IP addresses
    # from which they were created.
    def and_the_horse(u)
      addresses = Array(u).collect { |t| Spam::find_creation_ip_address(t) }
      blacklist_these_ips(addresses.uniq, verbose: true)
    end

    def catch_gists(old_gist = Gist.not_spammy.last, options = nil)
      Spam::Origin.console_origin = :console_catch_gists
      options ||= {}

      loop do
        new_gist = Gist.not_spammy.where(["gists.id > ?", old_gist.id]).first
        if new_gist
          old_gist = new_gist

          next unless new_gist.user
          next if new_gist.user.login == "nwdb-dev" # so prolific

          puts "\n" + "=" * 75

          if gist_is_patterny? new_gist
            gist_snip new_gist
            flag_these new_gist.user, "Gist spam (via catch_gists)"
            puts red("Flagged #{new_gist.user.login} (#{new_gist.user.id}) for Gist #{new_gist.id}: '#{new_gist.description}'")
            puts "\n" + "=" * 75
          else
            if new_gist.files_with_path.empty?
              first_filename = "N/A"
            else
              first_filename = new_gist.files_with_path.first.last
            end

            puts "Gist %d %-44s  %s (by %s)\n\t#{green('Did not match')} Filename: %-70s\n\tDescript: %-70s" %
                 [new_gist.id, new_gist.url,
                  blue(time_ago_in_words(new_gist.created_at) + " ago"),
                  (new_gist.user.nil? ? "Anonymous" : new_gist.user.login),
                  first_filename[0..69], new_gist.description.to_s[0..69]
                 ]
          end

        end
        take_a_break
      end
    ensure
      Spam::Origin.console_origin = :console
    end

    def gist_is_patterny?(gist)
      blob, first_filename = gist.files_with_path.first

      if blob && blob.data && blob.data.size < 1000000
        Spam.each_current_pattern("data") do |regex|
          return true if regex =~ blob.data
        end
      end

      if gist.description || first_filename
        Spam.each_current_pattern("filename") do |regex|
          return true if regex =~ gist.description if gist.description
          return true if regex =~ first_filename if first_filename
        end
      end

      false
    end

    def gist_is_naughty?(gist, filename_pattern, data_pattern)
      blob, first_filename = gist.files_with_path.first

      is_naughty = false
      is_naughty ||= gist.description =~ filename_pattern
      is_naughty ||= (first_filename && filename_pattern &&
                      first_filename =~ filename_pattern)
      is_naughty ||= (data_pattern && blob &&
                      blob.data =~ data_pattern)
      is_naughty
    end

    # Convenience wrappers

    def find_creation_ip_address(user)
      Spam::find_creation_ip_address(user)
    end

    def build_clusters(u, params = nil)
      Spam::build_clusters(u, params)
    end

    def has_blacklisted_payment_method?(user)
      BlacklistedPaymentMethod.exists_for_account?(user)
    end

    def results_gap(result1, result2)
      return -1 unless result1["created_at"].present? && result2["created_at"].present?
      result1["created_at"] - result2["created_at"]
    end

    def cluster_summary_line(user, idx = 0)
      begin
        email = user.try(:email)
        if user.spammy && email.present?
          email = red(email)
        end
        if user.payment_method.present?
          pmt_method = purple(user.payment_method.card_type.to_s)
        else
          pmt_method = ""
        end
        results = audit_log_payment_events(user)
        if results.present?
          pmt_times = red(results.count.to_s)
        else
          pmt_times = ""
        end
        if results.count == 2
          first_pmt_interval = (results.collect { |t| t["created_at"] }.min - user.created_at.to_i * 1000) / 1000.0
          first_pmt_interval = blue("%.01f" % first_pmt_interval)
          pmt_event_gap = results_gap results.first, results.last
          pmt_event_gap = blue("%.01f" % (pmt_event_gap / 1000.0))
          pmt_event_gap = " (#{first_pmt_interval} -> #{pmt_event_gap})"
        else
          pmt_event_gap = ""
        end
        "[%4d] [%7d] - %s %s %-20s  %s %s %s %s %s" %
          [idx, user.id, user.created_at.strftime("%Y-%m-%d %H:%M:%S"),
           user_status_summary(user), user.login,
           has_verified_email?(user) ? green("+") : " ", email,
           pmt_method, pmt_times, pmt_event_gap]
      rescue Faraday::ConnectionFailed => e
        "#{invert_yellow('RESCUED')} in cluster_summary_line: #{e}"
      end
    end

    # Dump a set of clusters
    def dump_clusters(clusters, idx = 0)
      tor = nil
      clusters.each do |cluster|
        cluster.each do |user|
          puts cluster_summary_line(user, idx)
          if tor.nil?
            tor = user.last_ip.present? && check_tor_node? && Spam.is_tor_node?(user.last_ip)
            @tor_ip = user.last_ip
          end
          idx += 1
        end
        puts "******"
      end
      puts purple("[  These are from a Tor exit node (#{@tor_ip})  ]") if tor
      nil
    end

    # The Wiki spam battle is under way.
    def dump_title(wiki)
      wiki.pages.collect(&:title).reject { |t| t =~ /Home/ }.first
    end

    def dump_wiki(u)
      Array(u).each_with_index do |user, i|
        if user.repositories.empty? ||
           !user.repositories.first.unsullied_wiki.exist? ||
           user.repositories.first.unsullied_wiki.pages.latest(1, 4).count < 2
          puts("[%3d] %s %-30s" % [i, user.id, user.login])
          next
        else
          title = dump_title(user.repositories.first.unsullied_wiki)
          spammy_key = GitHub::SpamChecker.check_text(title) ? red("S") : " "
          puts("[%3d] %s %-30s %s %s" % [i, user.id, user.login, spammy_key, title])
        end
      end
      nil
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

    def dump_edits(user, count = 5)
      puts collect_edits(user, count).join("\n")
    end

    def get_user_wiki(user)
      begin
        return nil if user.organization?
        return nil unless user.repositories.count == 1
        wiki = user.repositories.first.unsullied_wiki
        return nil unless wiki.exist?
        wiki
      rescue GitRPC::Error
        nil  # if we get GitRPC, etc., errors along the way, just return nil
      end
    end

    def get_wiki_page_titles(user)
      titles = []
      begin
        if wiki = get_user_wiki(user)
          titles = wiki.pages.collect &:title
        end
      rescue GitRPC::InvalidRepository
      end
      titles
    end

    def has_wiki_spam_title?(user)
      get_wiki_page_titles(user).find { |t| t =~ /download|cheap|credit card|free|ebook|epub|torrent|pharmacy|buy|casino|outlet|prescription/i }
    end

    # Examine all User accounts between the given ids for suspected Wiki spam,
    # and push the candidates for further review onto the manual spammy queue.
    #
    # start_id = 5000000
    # end_id  = 5100000
    #
    # catch_wiki_spam_candidates(start_id, end_id)
    #
    def catch_wiki_spam_candidates(start_id, end_id)
      User.not_spammy.where(["id > ? AND id < ?", start_id, end_id]).find_each do |user|
        if (title = has_wiki_spam_title?(user))
          puts "Pushing #{user.login} - '#{title}'"
          Spam.possible_spammer_queue.push(user.login)
        end
      end
    end

    # Look up profiles whose blog URL matches the given one
    def blogspam(blog)
      Profile.not_spammy.where(["blog like ?", blog]).joins(:user)
    end

    # For one or more URLs, return all the Users whose profiles list that as
    # their Profile blog.
    def grab_users_with_profile_blog(blogs)
      Array(blogs).inject([]) do |u, blog|
        puts "Blog #{blog}"
        p = blogspam(blog)
        puts "Processing #{p.count} profiles"
        u.concat p.collect(&:user).uniq
      end
    end

    # Re-queue search index purge jobs for all the passed-in User accounts.
    def index_purge(u)
      u = Array(u)
      u.each do |user|
        PurgeSpammyFromSearchIndexJob.perform_later(user.id)
      end
      u.count
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
    def invert_blue(str);   colorize(str, 44); end
    def invert_purple(str); colorize(str, 45); end
    def invert_aqua(str);   colorize(str, 46); end
    def invert_gray(str);   colorize(str, 47); end

  end # module Console
end # module Spam
