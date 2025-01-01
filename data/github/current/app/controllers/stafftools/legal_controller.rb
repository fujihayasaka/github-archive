# typed: true
# frozen_string_literal: true

class Stafftools::LegalController < StafftoolsController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:subpoena_discovery]

  # Digs up data for subpoenas
  def subpoena_discovery # rubocop:todo GitHub/UseRestfulActions
    data = {
      account_name: this_user.to_s,
      account_type: this_user.class.to_s,
      created_at: this_user.created_at.utc,
      plan: this_user.plan.to_s,
      billing_transactions: fetch_billing_transactions,
      emails: fetch_emails,
    }

    if this_user.organization?
      data.merge! fetch_org_teams
      data[:created_by] = nil # This stuff is not logged for orgs currently
      data[:creation_ip] = nil
      data[:other_accounts_from_ip] = []
    else
      data[:organizations] = this_user.organizations.map { |o| o.name }.sort
      data.merge! fetch_ip_addresses
      data[:recent_sessions] = fetch_sessions
      data[:logins] = fetch_audit_log_detail
    end

    render plain: JSON.pretty_generate(data)
  end

  private

  def fetch_billing_transactions
    this_user.billing_transactions.map do |t|
      txn_type = case
      when t.is_refund?; "Refund"
      when t.voided?; "Void"
      when t.success?; "Charge"
      else; "Failed"
      end
      {
        transaction_id: t.transaction_id,
        date: t.date,
        amount: t.amount.to_s,
        type: txn_type,
        card_number: t.card_number,
      }
    end
  end

  def query_audit_log(query_string, per_page: nil)
    options = {
      phrase:       query_string,
      current_user: current_user,
    }
    options[:per_page] = per_page unless per_page.nil?
    query = Audit::Driftwood::Query.new_stafftools_query(options)
    query.execute
  rescue # rubocop:todo Lint/RescueException
    Search::Results.empty
  end

  def fetch_emails
    # If the user isn't an org, `this_user.admins` will just be `[this_user]`
    ([this_user] + this_user.admins).flat_map do |admin|
      fetch_user_emails admin
    end.uniq
  end

  def fetch_user_emails(user)
    emails = user.emails.map { |e| e.email }
    emails << user.billing_email
    emails << user.profile.email unless user.profile.nil?
    emails << user.gravatar_email

    email_events = %w(
      user.create
      user.add_email
      user.remove_email
      user.initiate_email_unlink
      user.forgot_password
      user_email.request_verification
      user_email.confirm_verification
      billing.change_email
    )
    id = user.id
    actions = email_events.map { |e| "action:#{e}" }.join(" OR ")
    user_chunk = if user.user?
      "user_id:#{id}"
    else
      "user_id:#{id} OR (org_id:#{id} AND _exists_:org)"
    end
    query = "(#{user_chunk}) AND (#{actions})"

    if GitHub.driftwood_ade_queries_enabled?
      # Since users and orgs are stored in the same table, we can just check for both without needing to check the type
      query = <<~KQL
        webevents
        | where user_id == #{id} or (org_id == #{id} and org != "")
        | where action in ('#{email_events.join("','")}')
      KQL
    end

    hits = query_audit_log(query)
    emails += hits.map { |log| log["data"]["email"] }
    emails += hits.map { |log| log["data"]["old_email"] }

    emails.uniq.reject { |e| e.blank? }
  end

  def fetch_org_teams
    org_admins = this_user.admins

    admin_teams, write_teams = [:admin?, :write?].map do |perm|
      this_user.teams.select { |team| team_has_ability?(team, perm) }
    end

    read_teams = this_user.teams

    admin_members = extract_members admin_teams
    write_members = extract_members write_teams
    read_members  = extract_members read_teams

    admin_users = admin_members - org_admins
    write_users = write_members - admin_members
    read_users  = read_members - write_members - admin_members

    {
      read_write_admin_users: extract_usernames(admin_users),
      read_write_users: extract_usernames(write_users),
      read_only_users: extract_usernames(read_users),
      org_admins: extract_usernames(org_admins),
    }
  end

  def team_has_ability?(team, ability)
    repos = team.batched_repositories
    return false unless repos.any?
    repos.each do |repo|
      return true if team.ability(repo).send(ability)
    end
    false
  end

  def extract_members(teams)
    teams.map { |team| team.members }.flatten.uniq
  end

  def extract_usernames(users)
    users.map { |user| user.name }.sort
  end

  def fetch_ip_addresses
    ips = {}

    query = "user_id:#{this_user.id} AND action:user.create"
    if GitHub.driftwood_ade_queries_enabled?
      query = <<~KQL
        webevents
        | where user_id == #{this_user.id} and action == "user.create"
      KQL
    end

    hits = query_audit_log(query)
    if hits.any?
      creation_ip = hits.first["actor_ip"]
      ips[:creation_ip] = creation_ip

      query = [
        "-user_id:#{this_user.id}",
        "-actor_id:#{this_user.id}",
        "action:user.create",
        "actor_ip:#{creation_ip}",
      ].join(" AND ")

      if GitHub.driftwood_ade_queries_enabled?
        query = <<~KQL
          webevents
          | where user_id != #{this_user.id} and actor_id != #{this_user.id}
          | where action == "user.create" and actor_ip == "#{creation_ip}"
        KQL
      end

      hits = query_audit_log(query)
      ips[:other_accounts_from_ip] = hits.map { |log| log["user"] }.uniq.sort
    else
      ips[:other_accounts_from_ip] = []
    end

    ips
  end

  def fetch_sessions
    sessions = this_user.sessions.select { |session| session.impersonator_id.nil? }
    sessions.map do |session|
      {
        ip: session.ip,
        created_at: session.created_at.utc,
        last_active: session.accessed_at.utc,
        expired: !session.active?,
      }
    end
  end

  def fetch_audit_log_detail
    query = "user_id:#{this_user.id}"

    if GitHub.driftwood_ade_queries_enabled?
      query = <<~KQL
        webevents
        | where user_id == #{this_user.id}
      KQL
    end

    hits = query_audit_log(query, per_page: 9999)
    hits.map do |log|
      created_at = log["created_at"].present? ? log["created_at"] : log["@timestamp"]
      {
        ip: log["actor_ip"],
        timestamp: Time.at(created_at / 1000).utc,
      }
    end
  end
end
