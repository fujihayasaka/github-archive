# typed: true
# frozen_string_literal: true

require "forwardable"

module GitAuth
  class Gist
    TRUTHY_VALUES = [1, "1", true]
    extend Forwardable
    attr_reader :id, :user_id, :repo_name, :user_hidden, :is_public, :user_login, :user_display_login

    def self.with_name(name)
      id, user_id, repo_name, user_hidden, is_public = ApplicationRecord::Domain::Gists.connection.select_rows(Arel.sql(<<~SQL, name: name)).first
      SELECT id, user_id, repo_name, user_hidden, public
      FROM gists
      WHERE repo_name=:name
      SQL

      user_login, user_display_login = ApplicationRecord::Domain::Users.connection.select_rows(Arel.sql(<<-SQL, user_id: user_id)).first if user_id
        SELECT login, display_login
        FROM users
        WHERE id=:user_id
      SQL
      new id, user_id, repo_name, user_hidden, is_public, user_login, user_display_login, ::Gist.find_by(repo_name: name)
    end

    delegate [
      :flipper_id, #easy
      :feature_flag_enabled?, # feature flag actor
      :feature_flag_enabled_or_raise?, # feature flag actor
      :vexi_id, # for feature flag checks
      :route, # comes from Gist::DGit module
      :shard_path, # DGit
      :dgit_write_routes, # DGit
      :dgit_read_routes, # DGit
      :dgit_delegate, # DGit
      :dgit_delegate_for_update_refs_coordinator, # DGit
      :post_receive_hook_url, #easy
      :above_warn_quota?, #easy, Gist::Quota module
      :above_lock_quota?, #easy, Gist::Quota module
      :available?, #gitrpc
      :access, #rails-y, big
      :human_name, # for password deprecation identification
      :commits,
      :spokes_api,
      :spokes_api_context,
      :exists_on_disk?,
      :created_at,
      :updated_at,
      :deleted?,
      # Yeah, yeah.
      :nil?,
    ] => :@gist

    def initialize(id, user_id, repo_name, user_hidden, is_public, user_login, user_display_login, gist)
      @id = id
      @user_id = user_id
      @repo_name = repo_name
      @user_hidden = user_hidden
      @is_public = is_public
      @user_login = user_login
      @user_display_login = user_display_login
      @gist = gist
    end

    def public?
      TRUTHY_VALUES.include?(is_public)
    end

    def private?
      !public?
    end

    def user_hidden?
      TRUTHY_VALUES.include?(user_hidden)
    end
    alias_method :spammy?, :user_hidden?

    alias_method :gist_id, :repo_name

    def repository_spec
      # Using delegate above causes bootstrap warnings about delegating to
      # NilClass.  Hence, this method.
      @gist&.repository_spec
    end

    def full_name
      "#{user_login}/#{repo_name}"
    end
    alias_method :name_with_owner, :full_name

    def name_with_display_owner
      "#{user_display_login}/#{repo_name}"
    end

    def coalesce_dgit_updates?
      false
    end

    def locked?
      false
    end

    def disabled_private?
      false
    end

    def read_only?
      false
    end

    def fork?
      false
    end

    def archived?
      false
    end

    def target_for_conditional_access
      owner = User.find_by(id: user_id)
      return owner if owner
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end
  end
end
