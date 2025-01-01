# typed: true
# frozen_string_literal: true

# This is the runner for the ghe-org-admin-promote command, by way of
# script/ghe-org-admin-promote.
#
# It takes a single username (or nil, for all active site admins), an
# organization login (or nil for all organizations) and promotes the site admin
# (or all site admins) to admin on the organization (or all organizations).
#
class OrgAdminPromoter

  # Error class, raised if anything goes wrong during the promotion process.
  # Rescue this and display the message, as it's intended for user display.
  class Error < StandardError
  end

  attr_reader :username
  attr_reader :organization
  attr_reader :verbose

  def initialize(username:, organization: nil, verbose: false)
    @username = username
    @organization = organization
    @verbose = verbose
  end

  def run
    error "Admin promotion only works in enterprise" unless GitHub.enterprise?

    if username.nil?
      debug "retrieving list of site admins"
      # We're processing all site admins, so let's find their ids
      user_ids = User.connection.select_values(<<-SQL)
        SELECT id FROM users
        WHERE gh_role = 'staff'
        AND type = 'User'
        AND suspended_at IS NULL
        ORDER BY login
      SQL
    else
      # Verify that the user is valid
      user = User.find_by_login(username)

      if user.nil?
        error "#{username} does not exist."
      end

      if user.organization?
        error "#{username} is an organization, cannot promote as an admin."
      end

      if user.suspended?
        error "#{username} is suspended. Use `ghe-user-unsuspend` to unsuspend them first."
      end

      # Only check if user is a site admin when no organization is specified,
      # which allows promotion of a single non-site admin
      if organization.nil?
        unless user.site_admin?
          error "#{username} isn't a site admin. Use `ghe-user-promote` to promote them first."
        end
      end

      user_ids = [user.id]
    end

    if organization.nil?
      organizations = Organization.all
    else
      org = Organization.find_by_login(organization)
      if org.nil?
        error "#{organization} does not exist."
      end
      organizations = [org]
    end

    user_ids.each do |user_id|
      user = User.find(user_id)
      to_add = organizations.reject do |organization|
        organization.adminable_by?(user) || organization.login == "github-enterprise"
      end

      if to_add.empty?
        which_orgs = !organization.nil? ? organizations.first.login : "all organizations"
        log "#{user.login} is already an admin of #{which_orgs}, skipping"
      else
        to_add.each do |organization|
          log "Adding #{user.login} as an admin of #{organization.login}"
          unless organization.two_factor_requirement_met_by?(user)
            log "Warning: #{user.login} does not meet the two-factor authentication requirement of #{organization.login}, skipping"
            next
          end

          if organization.direct_member?(user)
            debug "Updating existing membership to admin"
            organization.update_member(user, action: :admin)
          else
            debug "Adding as new admin"
            organization.add_admin(user)
          end

          if organization.adminable_by?(user)
            log "#{user.login} is now an admin of the #{organization.login} organization"
            ssh_client = ENV.fetch("SSH_CLIENT", "").split(" ").first # just the IP address
            syslog "#{user.login} added as admin of #{organization.login} via ghe-org-admin-promote from #{ssh_client}"
          else
            error "Failed to set #{user.login} as an admin of the #{organization.login} organization. Please re-run this script with the -v option and send the output via #{GitHub.enterprise_support_url}"
          end
        end
      end
    end

    log "Done."
  end

  def error(msg)
    raise Error, msg
  end

  def log(msg)
    return if Rails.env.test?
    STDERR.puts " --> #{msg}"
  end

  def debug(msg)
    return unless @verbose
    return if Rails.env.test?
    STDERR.puts "  -> #{msg}"
  end

  def syslog(msg)
    return if Rails.env.test?
    Progeny::Command.new "logger", msg
  end
end
