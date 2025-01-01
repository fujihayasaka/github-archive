# typed: true
# frozen_string_literal: true

module User::NoticesDependency
  include Kernel
  ORGANIZATION_NOTICES = {
    advanced_security_self_serve_trial_survey: "advanced_security_self_serve_trial_survey",
    saml_sso_banner: "saml_sso_banner",
    enterprise_trial_warning_banner: "enterprise_trial_warning_banner",
    enterprise_trial_expired_banner: "enterprise_trial_expired_banner",
    enterprise_survey_banner: "enterprise_survey_banner",
    add_successor_prompt: "add_successor_prompt",
    saml_prompt: "saml_prompt",
    invoiced_customer_set_spending_limit: "invoiced_customer_set_spending_limit",
    depleted_prepaid_credits: "depleted_prepaid_credits",
    enterprise_trial_banner: "enterprise_trial_banner",
    demo_repository_notification: "demo_repository_notification",
    enterprise_trial_onboarding: "enterprise_trial_onboarding",
    projects_beta_legacy_warning: "projects_beta_legacy_warning",
    pages_private_prompt: "pages_private_prompt",
    ip_allowlist_ipv6: "ip_allowlist_ipv6",
    ghas_trial_upsell_banner: "ghas_trial_upsell_banner",
    security_analysis_ghas_trial_banner: "security_analysis_ghas_trial_banner",
    business_org_transfer: "business_org_transfer",
    larger_runners_setup_default_dialog_available: "larger_runners_setup_default_dialog_available",
    invalid_azure_subscription: "invalid_azure_subscription",
    code_view_org_copilot_popover: "code_view_org_copilot_popover",
    copilot_enterprise_trial_expired_banner: "copilot_enterprise_trial_expired_banner",
  }.freeze

  REPOSITORY_NOTICES = %w(cta_marketplace_ci first_time_contributor_issues_banner
    first_time_contributor_pull_requests_banner marketplace_project_management_issues_banner popular_repo_successor_prompt repo_default_branch_rename
    repo_parent_default_branch_rename discussions_tab discussions_spotlight discussions_categories discussions_polls_category discussions_new_discussion
    sculk_protect_this_branch try_file_level_commenting repo_suggested_workflows github_models_paid_usage_banner_repo deploy_to_pages_banner
  ).freeze

  BUSINESS_NOTICES = %w(
    invoiced_customer_set_spending_limit
    depleted_prepaid_credits
    ip_allowlist_ipv6
    trial_onboarding
    trial_onboarding_banner
    enterprise_survey_banner
    larger_runners_setup_default_dialog_available
    advanced_security_sidebar_promotion
    org_upgrade_onboarding
    copilot_getting_started
    dfd_new_tasks_enable_cb_nudge
    dfd_new_tasks_create_org_nudge
    dfd_new_tasks_create_repo_nudge
    dfd_new_tasks_add_code_nudge
  ).freeze

  PROJECT_NOTICES = %w(
    project_migration_notice
    project_migration_complete_notice
    memex_without_limits_beta
    memex_issue_types_rename_prompt
  ).freeze

  # Figures out which notices to show on the user's dashboard.
  #
  # Returns an Array of notice names as Strings.
  def notices_for_dashboard
    T.bind(self, User)
    return @notices_for_dashboard unless @notices_for_dashboard.nil?
    @notices_for_dashboard =
      DashboardNoticesStore.get_for_user_id(self.id)
        .rescue { |result| report_failure(result, :notices_for_dashboard, nil) }
        .value { [] }
        .map { |notice| notice.name }
  end

  # Activates a notice for the user. Safe to call multiple times with
  # the same value. If the user has dismissed the notice, it will not show up
  # again.
  #
  # name - String or symbol corresponding to the views/notices partial to show.
  #
  # Returns nothing.
  def activate_notice(name)
    T.bind(self, User)
    return if name.blank?
    name = name.to_s
    @notices_for_dashboard = nil
    DashboardNoticesStore.add(self.id, name)
      .rescue { |result| report_failure(result, :activate_notice, name) }
  end

  # Reset the notices for the user. This will not cause all notices to show up
  # again, but it will cause the notices_for_dashboard method to re-query the notices
  def reset_notices
    @notices_for_dashboard = nil
  end

  # Forcefully activates a notice even if the user has dismissed it in the
  # past.
  #
  # name - String or symbol corresponding to the views/notices partial to hide.
  #
  # Returns nothing.
  def activate_notice!(name)
    delete_notice(name)
    activate_notice(name)
  end

  # Deactivates (hides) a notice for the user. This notice will never show up
  # again. If you want to re-use the notice, you should use delete_notice so
  # subsequent activate_notice calls work as expected.
  #
  # name - String or symbol corresponding to the views/notices partial to hide.
  #
  # Returns nothing.
  def deactivate_notice(name)
    T.bind(self, User)
    return if name.blank?
    name = name.to_s
    @notices_for_dashboard = nil
    DashboardNoticesStore.deactivate(self.id, name)
      .rescue { |result| report_failure(result, :deactivate_notice, name) }
  end

  # Deletes a notice for the user. If activate_notice is called after this
  # notice, the notice will show up again even if the user has dismissed it.
  #
  # name - String or symbol corresponding to the views/notices partial to hide.
  #
  # Returns nothing.
  def delete_notice(name)
    T.bind(self, User)
    return false if name.blank?
    name = name.to_s
    @notices_for_dashboard = nil
    DashboardNoticesStore.delete(self.id, name)
      .rescue { |result| report_failure(result, :delete_notice, name) }
  end

  # Deletes all notices for the user.
  #
  # Returns nothing.
  def delete_notices
    T.bind(self, User)
    @notices_for_dashboard = nil
    DashboardNoticesStore.delete_all_for_user(self.id)
  end

  # Set User Key Value for Notice
  #
  # notice - key to be added
  def dismiss_notice(notice_name, expires: nil, kv_store: Notices::Kv.store)
    T.bind(self, User)
    return unless notice = get_notice(notice_name)
    return if dismissed_notice?(notice_name, kv_store:)

    if expires.present?
      kv_store.set("user.dismissed_notice.#{notice.name}.#{id}", Time.now.utc.iso8601, expires: expires)
    else
      kv_store.set("user.dismissed_notice.#{notice.name}.#{id}", Time.now.utc.iso8601)
    end
  end

  # Dismisses the global enterprise announcement for a given user.
  #
  # uuid - the UUID of the enterprise announcement
  def dismiss_global_enterprise_announcement(uuid:, kv_store: Notices::Kv.store)
    T.bind(self, User)
    announcement = GitHub::EnterpriseAnnouncement.get_announcement

    if uuid.blank? || announcement.text.blank? || announcement.uuid != uuid
      error = "Announcement UUID must be present and unique"
      report_failure(StandardError.new(error), :global_announcement_banner, uuid)
      return error
    end

    kv_store.set("enterprise:announcement:dismiss:#{id}", uuid)
    nil
  end

  # Public – Check whether or not a user has dismissed the global enterprise announcement banner.
  # Storage format is enterprise:announcement:dismiss:<user-id> = "<banner-uuid>"
  #
  # Returns false if the user has not dismissed the global enterprise announcement banner.
  # Return true otherwise.
  def has_dismissed_announcement?(uuid:, kv_store: Notices::Kv.store)
    T.bind(self, User)
    (kv_store.get("enterprise:announcement:dismiss:#{id}").value { nil } == uuid)
  end

  # Delete User Key Value for Notice
  #
  # notice - key to be deleted
  def reset_notice(notice, kv_store: Notices::Kv.store)
    T.bind(self, User)
    kv_store.del("user.dismissed_notice.#{notice}.#{id}")
  end

  # Get User Key Value for Notice
  #
  # notice - key to check for in key values
  #
  # Returns true or false
  def dismissed_notice?(notice_name, kv_store: Notices::Kv.store)
    T.bind(self, User)
    return unless notice = get_notice(notice_name)
    return true if notice.hide_from_new_user? && T.unsafe(self).created_at > notice.effective_date
    ActiveRecord::Base.connected_to(role: :reading) do
      kv_store.get("user.dismissed_notice.#{notice.name}.#{id}").value { true }.present?
    end
  end

  # The time in UTC that the notice was dismissed at. Nil if no time was set.
  #
  # Returns: Time or nil
  def notice_dismissed_at(notice_name, org = nil, for_whole_org: false, kv_store: Notices::Kv.store)
    T.bind(self, User)
    if org.nil?
      return nil unless notice = get_notice(notice_name)
      return nil if notice.hide_from_new_user? && T.unsafe(self).created_at > notice.effective_date

      value = ActiveRecord::Base.connected_to(role: :reading) do
        kv_store.get("user.dismissed_notice.#{notice.name}.#{id}").value!
      end
    else
      return nil unless ORGANIZATION_NOTICES.include?(notice_name.to_sym)

      value = ActiveRecord::Base.connected_to(role: :reading) do
        user_id = for_whole_org ? nil : id
        kv_store.get("user.dismissed_organization_notice.#{notice_name}.#{org.id}.#{user_id}").value!
      end
    end
    return if value.nil?

    begin
      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
  end

  # Delete User key value for a repository notice
  #
  # notice - key to be deleted
  # repository_id - the ID of the Repository for which the notice was made
  #
  # Returns nothing
  def reset_repository_notice(notice, repository_id:, kv_store: Notices::Kv.store)
    T.bind(self, User)
    kv_store.del("user.dismissed_repository_notice.#{notice}.#{repository_id}.#{id}")
  end

  # Set User Key Value for Org Notice
  #
  # notice - key to be added
  # org - an Organization object
  def dismiss_organization_notice(notice, org, for_whole_org: false, kv_store: Notices::Kv.store)
    T.bind(self, User)
    return unless ORGANIZATION_NOTICES.include?(notice.to_sym)

    if !dismissed_organization_notice?(notice, org, for_whole_org: for_whole_org, kv_store:)
      user_id = for_whole_org ? nil : id
      kv_store.set("user.dismissed_organization_notice.#{notice}.#{org.id}.#{user_id}", Time.now.utc.iso8601)
    end
  end

  # Get User Key Value for Org Notice
  #
  # notice  - key to check for in key values
  # org     - an Organization object
  #
  # Returns a Boolean.
  def dismissed_organization_notice?(notice_name, org, for_whole_org: false, kv_store: Notices::Kv.store)
    T.bind(self, User)
    return false unless ORGANIZATION_NOTICES.include?(notice_name.to_sym)

    ActiveRecord::Base.connected_to(role: :reading) do
      user_id = for_whole_org ? nil : id
      kv_store.get("user.dismissed_organization_notice.#{notice_name}.#{org.id}.#{user_id}").value { true }.present?
    end
  end

  # Delete User key value for a Org notice
  #
  # notice - key to be deleted
  # org - an Organization object for which the notice was made
  #
  # Returns nothing
  def reset_organization_notice(notice, org, for_whole_org: false, kv_store: Notices::Kv.store)
    T.bind(self, User)
    user_id = for_whole_org ? nil : id
    kv_store.del("user.dismissed_organization_notice.#{notice}.#{org.id}.#{user_id}")
  end

  # Get User Key Value for a repository notice
  #
  # notice - key to check for in key values
  # repository_id - a Repository database ID
  #
  # Returns a Boolean.
  def dismissed_repository_notice?(notice, repository_id:, kv_store: Notices::Kv.store)
    T.bind(self, User)
    ActiveRecord::Base.connected_to(role: :reading) do
      key = "user.dismissed_repository_notice.#{notice}.#{repository_id}.#{id}"
      kv_store.get(key).value { notice } == notice
    end
  end

  # Set User Key Value for repository notice
  #
  # notice - key to be added
  # repository_id - a Repository database ID
  def dismiss_repository_notice(notice, repository_id:, kv_store: Notices::Kv.store)
    T.bind(self, User)
    if REPOSITORY_NOTICES.include?(notice)
      if !dismissed_repository_notice?(notice, repository_id: repository_id)
        kv_store.set("user.dismissed_repository_notice.#{notice}.#{repository_id}.#{id}", notice)
      end
    end
  end

  # Get User Key Value for Business Notice
  #
  # notice   - key to check for in key values
  # business - an Business object
  #
  # Returns a Boolean.
  def dismissed_business_notice?(notice, business_id:, for_whole_business: false, kv_store: Notices::Kv.store)
    T.bind(self, User)
    ActiveRecord::Base.connected_to(role: :reading) do
      user_id = for_whole_business ? nil : id
      kv_store.get("user.dismissed_business_notice.#{notice}.#{business_id}.#{user_id}").value { true }.present?
    end
  end

  # Set User Key Value for Business Notice
  #
  # notice - key to be added
  # business - an Business object
  def dismiss_business_notice(notice, business_id:, for_whole_business: false, kv_store: Notices::Kv.store)
    T.bind(self, User)
    if BUSINESS_NOTICES.include?(notice)
      user_id = for_whole_business ? nil : id
      kv_store.set("user.dismissed_business_notice.#{notice}.#{business_id}.#{user_id}", notice)
    end
  end

  # Delete User key value for a business notice
  #
  # notice - key to be deleted
  # business_id - the ID of the business for which the notice was made
  #
  # Returns nothing
  def reset_business_notice(notice, business_id:, for_whole_business: false, kv_store: Notices::Kv.store)
    T.bind(self, User)
    user_id = for_whole_business ? nil : id
    kv_store.del("user.dismissed_business_notice.#{notice}.#{business_id}.#{user_id}")
  end

  # Set User Key Value for a Project notice
  #
  # notice - key to be added
  # project - the ID of the project
  def dismiss_project_notice(notice, project_id:)
    T.bind(self, User)
    return unless PROJECT_NOTICES.include?(notice)
    Memex::KV.store.set("user.dismissed_project_notice.#{notice}.#{project_id}.#{id}", notice)
  end

  # Get User Key Value for a Project notice
  #
  # notice - key to check for in key values
  # project - the id of the project
  #
  # Returns a Boolean.
  def dismissed_project_notice?(notice, project_id:)
    T.bind(self, User)
    ActiveRecord::Base.connected_to(role: :reading) do
      Memex::KV.store.get("user.dismissed_project_notice.#{notice}.#{project_id}.#{id}").value { notice } == notice
    end
  end

  # Delete User key value for a Project notice
  #
  # notice - key to be deleted
  # project - the ID of the project
  #
  # Returns nothing
  def reset_project_notice(notice, project_id:)
    T.bind(self, User)
    Memex::KV.store.del("user.dismissed_project_notice.#{notice}.#{project_id}.#{id}")
  end

  private

  # Report the error and repackage the error back into a Result
  #
  # error - the error to report_failure
  #
  # Returns a new error result.
  def report_failure(error, operation, notice_name)
    Failbot.report(error, operation: operation, notice_name: notice_name, app: "github-user")
    GitHub::Result.error error
  end

  def get_notice(notice_name)
    if notice = UserNotice.find(notice_name)
      notice
    else
      error = ArgumentError.new("unregistered notice: #{notice_name.inspect}")
      error.set_backtrace(caller)
      case GitHub.missing_user_notice_behavior
      when :failbot
        report_failure(error, caller_locations.first&.label, notice_name)
      else
        raise(error)
      end
      nil
    end
  end
end
