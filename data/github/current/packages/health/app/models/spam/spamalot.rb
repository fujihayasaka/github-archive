# typed: false
# frozen_string_literal: true

module Spam
  class Spamalot
    attr_accessor :history, :q
    attr_reader :user
    attr_writer :sp, :u, :v, :x, :z

    def initialize(queue = Spam.possible_spammer_queue)
      @q = queue
      @history = []
    end

    # This is the cball I call from the console
    def cball
      dump_clusters build_clusters(x.last 50), [x.count - 50, 0].max
      if x.count > 50
        puts yellow("Skipped first #{x.count - 50} of x")
      end
      puts "*" * 80
      dump_clusters build_clusters(v.last 50), [v.count - 50, 0].max
      if v.count > 50
        puts yellow("Skipped first #{v.count - 50} of v")
      end
      puts v.count
      puts "z" * 20
      dump_clusters build_clusters z
    end
    alias_method :c, :cball

    def sp
      @sp ||= SpamPattern.matches_for(user)
    end

    alias_method :h, :history

    # Users at the same IP address as self.user
    def u
      # puts "About to return from u()" unless user
      return [] unless user
      # puts "Have a user, it's #{user.login}, grabbing nball"
      @u ||= nball user
    end

    # Non-spammy users in self.x
    def v
      @v ||= x.reject { |t| t.reload.spammy || t.never_spammy? }
    end

    # Users at the same C-class as self.user.last_ip
    def x
      return [] unless @user
      @x ||= similar_ip user.last_ip
    end

    def z
      @z ||= v.select { |t| gists_per_hour(t) > 5 }
    end

    # This is the actuall cball method from .irbrc
    def similar_ip(ip)
      results = []
      ip = ip.last_ip if ip.respond_to? :last_ip
      return results if ip.nil?

      if ip =~ /\d+\.\d+\.\d+/
        ip = $~[0] + ".%"
        results = ActiveRecord::Base.connected_to(role: :reading) { User.where("last_ip like ?", ip).order(:created_at) }
      end
      results
    end

    def user=(new_user)
      if new_user.is_a? String
        puts "Finding user with login #{new_user}"
        new_user = dat(new_user)
        if new_user.is_a? User
          asum new_user
        else
          puts "Fail! There is no user with that login"
          return
        end
      end
      @u = nil
      @v = nil
      @x = nil
      @z = nil
      @sp = nil
      @user = new_user
    end

    # This is basically the q.get that I call from the console
    def get(params = nil)
      params ||= {}
      params[:all] = true
      skip_drop = false
      while q.count > 0 do
        # puts "u is present, dropping" if u.present?
        q.drop_these(u) if u.present? && !skip_drop
        q.drop_this(user) if user&.organization?
        self.user = q.get_next(params)
        # puts "pulled #{user} from q (remaining: #{q.count})"
        add_to_history user
        # puts 'Added to history, dumping u'
        dump_clusters build_clusters(u.last 50), [u.count - 50, 0].max
        if u.count > 50
          puts yellow("Skipped first #{u.count - 50} of u")
        end
        asum
        unless user.can_be_flagged?
          if user.paid_plan? && user.billing_transactions.none?(&:success?)
            puts red("\nWhoa, hold up! #{user.login} has no real transactions, and may be bogus!  Check https://github.com/stafftools/#{user.login}/billing")
          elsif user.hammy?
            puts green("\n#{user.login} is whitelisted. Moving on.")
            if entry
              entry.drop actor: my_bad_self
            end
            next
          end
        end
        skip_drop = user.spammy &&
                    sp.any? { |t| t.attribute_name == "last_ip" && t.flag }
        if sp.empty? || !skip_drop
          # if sp.empty?
          # puts "Found no matching SpamPatterns. Stopping."
          # else
          # puts "Found no 'last_ip' pattern among the #{sp.count} matching SpamPattern(s)"
          # end
          break
        else
          entry.drop(actor: my_bad_self) if entry
        end
      end
      puts "Queue Size: #{q.count}"
    end
    alias_method :g, :get

    def gr
      get(from: "right")
    end

    # Find the SpamQueueEntry matching the current user (if any, and if the
    # current queue supports :spam_queue, meaning it's a NewUserQueue)
    def entry_for_user(this_user)
      return nil unless this_user && q.respond_to?(:spam_queue)
      entry = q.spam_queue.entry_for_user(this_user)
    end

    def entry
      entry_for_user(user)
    end

    def add_to_history(user)
      return unless user
      history << user
      # Don't need to track more than this
      (history.count - 100).times do
        history.shift
      end
    end

    def agent
      user.sessions.last.user_agent
    end

    def dropx(load_x_implicitly = false)
      if load_x_implicitly || @x.present? # don't call self.x, as it would load
        q_start = q.count
        puts "Dropping all #{x.count} users from PSQ (count: #{q_start})"
        q.drop_these(x)
        puts "Queue size: #{q.count} (Diff: #{q_start - q.count})"
      else
        puts "Not loading x implicitly; skipping"
        entry.drop(actor: my_bad_self) if entry
      end
    end

    # Dump all the logins and ips and format something like this:
    #   matthew7oic1sbl          152.226.6.206   X  william0121cwo@aolmailgroup.com
    #   nathan3eez0tblo          152.226.6.206   X  daniel8990wpi@aolmailgroup.com
    #   amdz64                   152.226.6.206   X  1303139H@student.tp.edu.sg
    #   XiaoYaoL                 152.226.6.206   X  LiuJessica94@gmail.com
    def dump_logins_and_ips
      x.each do |t|
        puts "%-25s %-15s %s  %s" % [t.login[0..24], t.last_ip, (t.spammy ? "X" : " "), t.email]
      end
      nil
    end

    def asum(this_user = nil)
      puts activity_summary(this_user || user)
    end

    def dc
      dump_comments user
    end

    def df
      following = user.following.count
      puts "#{user.login} is following #{following} users:" if following > 0
      user.following.each do |t|
        puts "%-25s %-15s %s  %s" % [t.login[0..24], t.last_ip, (t.spammy ? "X" : " "), t.email]
      end
      nil
    end

    def dff
      followers = ActiveRecord::Base.connected_to(role: :reading) { user.followers.count }
      puts "#{user.login} is followed by #{followers} users:" if followers > 0
      user.followers.each do |t|
        puts "%-25s %-15s %s  %s" % [t.login[0..24], t.last_ip, (t.spammy ? "X" : " "), t.email]
      end
      nil
    end

    def dh
      dump_clusters build_clusters history
    end

    def du
      dump_clusters build_clusters u
    end

    def dv
      dump_clusters build_clusters v
    end

    def dx
      dump_clusters build_clusters x
    end

    def dz
      dump_clusters build_clusters z
    end

    def gs(idx = 0)
      gist_snip user.gists[idx] if user.gists[idx].present?
    end

    # Flag a User or an Array of Users as spammy, with a default
    # reason and a default actor (@erebor) set for audit logging.
    def flag_these(users, reason = "Fake account spam")
      # Convenience so I can pass a single user in here
      users = Array(users)
      to_drop = []
      users.select { |us| !us.spammy }.each do |this_user|
        if this_entry = entry_for_user(this_user)
          puts "Found entry for #{this_user.login}: doing resolve thing"
          resolve_entry_as_spammy this_entry, reason
        else
          puts "Did not find entry for #{this_user.login}: doing flag-and-drop thing"
          to_drop << this_user
          this_user.mark_as_spammy(reason: reason, actor: my_bad_self)
        end
      end
      q.drop_these(to_drop)
    end
    alias :f  :flag_these

    # Unflag an arbitrarily-large group of accounts
    def unflag_these(u)
      Array(u).select { |us| us.spammy }.each do |this_user|
        if this_entry = entry_for_user(this_user)
          this_entry.resolve_as_unflagged actor: my_bad_self
        else
          this_user.mark_not_spammy actor: my_bad_self
        end
      end
      nil
    end

    def pls
      flag_these user, "Profile/login spam"
    end

    def ris
      flag_these user, "Repo/Issue spam"
    end

    def rws
      flag_these user, "Repo/Wiki spam"
    end

    def qf(reason = nil)
      puts "Flagging user: #{user.login}"
      if reason
        flag_these user, reason
      else
        flag_these user
      end
    end

    def qfg
      qf "Gist spam"
    end

    def qfa(reason = nil)
      puts "Flagging the #{user.admins.count} admins for Org #{user}"
      if reason
        flag_these user.admins, reason
      else
        flag_these user.admins
      end
    end

    def qfo(reason = nil)
      puts "Flagging the #{user.organizations.count} organizations belonging to #{user}"
      if reason
        flag_these user.organizations, reason
      else
        flag_these user.organizations
      end
    end

    def qfu(arg = nil)
      if arg.nil?
        puts "Flagging the #{u.count} users sharing #{user.login}'s IP of #{user.last_ip}"
        flag_these u
      elsif arg.is_a? Range
        slice = u[arg]
        puts "Flagging the #{slice.count} unflagged users in u[#{arg}] and sharing #{user.login}'s IP of #{user.last_ip}"
        flag_these slice
      elsif arg.is_a? Integer
        if arg > (u.count - 1)
          puts "Can't flag index #{arg} in u, which only has #{u.count} elements."
        else
          puts "Flagging user #{u[arg].try(:login)} (s.u[#{arg}]), who shares #{user.login}'s IP of #{user.last_ip}"
          flag_these u[arg]
        end
      else
        puts "I don't know what to do with argument: #{arg}, which is a #{arg.class}"
      end
    end

    def qfv(arg = nil)
      if arg.nil?
        puts "Flagging the #{v.count} unflagged users sharing a /24 with #{user.login}'s IP of #{user.last_ip}"
        flag_these v
      elsif arg.is_a? Range
        slice = v[arg]
        puts "Flagging the #{slice.count} unflagged users in v[#{arg}] and sharing a /24 with #{user.login}'s IP of #{user.last_ip}"
        flag_these slice
      elsif arg.is_a? Integer
        if arg > (v.count - 1)
          puts "Can't flag index #{arg} in v, which only has #{v.count} elements."
        else
          puts "Flagging user #{v[arg].try(:login)} (v[#{arg}]), who shares a /24 with #{user.login}'s IP of #{user.last_ip}"
          flag_these v[arg]
        end
      else
        puts "I don't know what to do with argument: #{arg}, which is a #{arg.class}"
      end
    end

    def csr
      puts "Clearing spammy reason for #{user.login} (was '#{user.spammy_reason}')"
      user.update_attribute :spammy_reason, nil
    end

    def uf
      puts "Unflagging user: #{user.login}"
      unflag_these user
    end

    def w
      puts "Whitelisting user: #{user.login}"
      if entry
        entry.resolve_as_whitelisted actor: my_bad_self
      else
        white user
      end
    end
  end
end
