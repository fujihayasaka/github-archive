# typed: false
# frozen_string_literal: true

class Stafftools::LdapController < StafftoolsController
  before_action :enterprise_required
  before_action :ensure_user_exists, only: [:update, :sync]
  before_action :ensure_team_exists, only: [:update_team, :sync_team]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index], optional: true

  QUERY_LIMIT = 150

  def index
    config = GitHub.auth.configuration
    uid    = @uid = config[:uid]
    limit  = params[:query_limit].to_i
    limit  = QUERY_LIMIT unless limit > 0

    # query_limit is not the pagination limit.
    # It's the number of entries we want to return from the ldap server.
    if params[:query].present?
      results = find_personas(uid, params[:query], limit)

      @search_results = Array(results)

      if !@search_results.empty?
        # filter out any results with a blank UID
        # See: https://github.com/github/github/issues/29026
        @search_results.reject! { |entry| entry[uid].first.nil? }

        # FIXME: Search results can sometimes contain dupes
        @search_results.uniq! { |entry| entry.dn }

        @search_results.sort! { |u1, u2| u1[uid].first.casecmp(u2[uid].first) }
      end

      @limited = limit if @search_results.count >= limit
      @search_results = @search_results.paginate(page: current_page)

      # match this pages' results to User records
      users = User.find_by_ldap_mappings(*@search_results.entries.map(&:dn))
      users = Hash[users.map { |u| [u.ldap_dn, u] }]
      # falling back to normalized login
      users_by_login = User.with_logins(*@search_results.entries.map { |e| User.standardize_login(e[uid].first).downcase })
      users_by_login = Hash[users_by_login.map { |u| [u.login, u] }]

      @search_results.each do |entry|
        entry[:gh_login]  = login = User.standardize_login(entry[uid].first).downcase
        entry[:signed_in] = users[entry.dn] || users_by_login[login]
      end
    end

    render "stafftools/ldap/index"
  end

  def create
    config  = GitHub.auth.configuration
    domains = GitHub.auth.ldap_domains

    entry = nil
    domains.each_value do |domain|
      result = domain.search({
        filter: Net::LDAP::Filter.eq(config[:uid], params[:uid]),
      })

      entry = result.first if !result.nil? && !result.empty?
    end

    if User.find_by_login(params[:login])
      message = "User `#{params[:login]}` already exists."
    elsif entry
      begin
        user, message = GitHub.auth.create_user(params[:login], entry)
      rescue ActiveRecord::RecordInvalid => e
        message = e.message
      end
    else
      message = "User account could not be created: '#{params[:uid]}' could not be found."
    end

    if request.xhr?
      if user
        render status: :ok, plain: "User created successfully."
      else
        render status: :unprocessable_entity, plain: message
      end
    end
  end

  def update
    update_ldap_dn_for(this_user, this_user.login, params[:ldap_dn])
  end

  def sync # rubocop:todo GitHub/UseRestfulActions
    this_user.enqueue_sync_job

    flash[:notice] = "Job queued to synchronize #{this_user} with LDAP."
    redirect_to :back
  end

  def update_team # rubocop:todo GitHub/UseRestfulActions
    if Team::Editor.update_team(this_team, ldap_dn: params[:ldap_dn], updater: current_user)
      flash[:notice] = "#{this_team.name}’s LDAP DN changed successfully."
    else
      flash[:error] = "Unable to change #{this_team.name}’s LDAP DN. #{this_team.errors.full_messages.first}."
    end

    redirect_to :back
  end

  def sync_team # rubocop:todo GitHub/UseRestfulActions
    this_team.enqueue_sync_job

    flash[:notice] = "Job queued to synchronize #{this_team.name} with LDAP."
    redirect_to :back
  end

  private

  def find_personas(uid, query, limit = nil)
    options = {
      filter: personas_filter(uid, query),
      attributes: ["cn", uid],
      size: limit,
    }

    ldap_groups = all_groups
    if ldap_groups.empty?
      rs = GitHub::LDAP.search.find_personas(options)
    else
      rs = GitHub::LDAP.search.find_personas(options) do |persona|
        ldap_groups.any? { |g| g.is_member?(persona) }
      end
    end

    if rs.search_error? && rs.entries.empty?
      flash[:error] = "We had a problem retrieving users. The response was (#{rs.code}) #{rs.message}."
      return
    end

    # Only return results if there are no auth groups in the filter
    # or there are auth groups and we found them.
    #
    # Do not return results if we cannot find the auth groups configured.
    if !auth_groups.empty? && ldap_groups.empty?
      []
    else
      rs.entries
    end
  end

  def all_groups
    return auth_groups if auth_groups.empty?

    GitHub::LDAP.search.groups(*auth_groups).map do |entry|
      GitHub.auth.strategy.load_group(entry)
    end
  end

  def auth_groups
    GitHub.ldap_auth_groups
  end

  def personas_filter(uid, query)
    Net::LDAP::Filter.contains(uid, query) | Net::LDAP::Filter.contains("cn", query)
  end

  def update_ldap_dn_for(subject, subject_name, ldap_dn)
    if subject.map_ldap_entry(ldap_dn)
      flash[:notice] = "#{subject_name}’s LDAP DN changed to #{ldap_dn}."
    else
      flash[:error] = "Unable to change #{subject_name}’s LDAP DN. #{subject.ldap_mapping.errors.full_messages.first}."
    end

    redirect_to :back
  end
end
