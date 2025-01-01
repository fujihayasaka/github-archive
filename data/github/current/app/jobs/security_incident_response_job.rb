# typed: false
# frozen_string_literal: true

class SecurityIncidentResponseJob < ApplicationJob
  queue_as :spam

  retry_on_dirty_exit

  exempt_from_tenant_context_requirement

  attr_accessor :batch_count, :batch_index, :errors, :users_by_id
  attr_reader :actor, :incident_response_id

  def perform(actor:, id:, incident_responses:)
    @actor = actor
    @incident_response_id = id
    @users_by_id = {}
    preload_users_by_id!(incident_responses)
    @batch_index = 0
    incident_responses.each do |response|
      handle_response(response)
    end
  end

  private

  # Private: Preload the users specified in the incident_responses.
  #
  # incident_responses - Array of hashes with a :user_id or :user_ids key.
  #
  # Assigns @users_by_id
  def preload_users_by_id!(incident_responses)
    user_ids = incident_responses.flat_map do |response|
      user_ids_for_response(response).map do |user_id|
        is_database_id = user_id.to_i.to_s == user_id.to_s
        if is_database_id
          user_id
        else
          begin
            Platform::Helpers::NodeIdentification.from_global_id(user_id.to_s).last
          rescue Platform::Errors::NotFound
            nil
          end
        end
      end
    end
    @batch_count = user_ids.size
    users = if GitHub.flipper[:unscope_security_ir_job_in_proxima].enabled?
      GitHub::CurrentTenant.unscope do
        User.where(id: user_ids)
      end
    else
      User.where(id: user_ids)
    end

    users.each do |user|
      @users_by_id[user.id.to_s] = user
      @users_by_id[user.global_relay_id] = user
    end
  end

  def user_ids_for_response(response)
    Array(response[:user_id]) + Array(response[:users]).map { |u| u[:id] }
  end

  def users_for_response(response)
    Array(response[:user_id]) + Array(response[:users])
  end

  # Private: Parse the response to run all remediations and potentially write a staffnote
  # and notify the user, and publish a SecurityIncidentRemediation event.
  #
  # response - A hash with the structure of Inputs::SecurityIncidentResponse
  def handle_response(response)
    users_for_response(response).each_with_index do |user_data, _user_index|
      # batch_index starts at 1 so that knowing if a job is the last one is batch_count == batch_indx
      @batch_index += 1
      @errors = []
      if user_data.is_a?(String)
        user_id = user_data
      else
        user_id = user_data[:id]
        user_template_data = user_data[:data]
      end
      user = users_by_id[user_id.to_s]

      successful_remediations, failed_remediations = with_write do
        run_remediations(user, response, user_template_data)
      end

      GlobalInstrumenter.instrument("security_incident_response.remediation_complete",
        actor: actor,
        account: user,
        account_id: String(user&.global_relay_id || user_id),
        errors: errors,
        failed_remediations: failed_remediations.sort,
        successful_remediations: successful_remediations.sort,
        staffnote: response[:staffnote],
        email_body_template: response[:notify].try(:[], :template),
        incident_response_id: incident_response_id,
        batch_count: batch_count,
        batch_index: batch_index,
        inputs: response.to_json,
      )
    end
  end

  # Private: Run the remediations for a particular user and keep track of which
  # succeed and which fail.
  # When the user was not found or is an employee all remediations are marked as failed.
  #
  # user - The account to do these remediations for.
  # response - A hash with the structure of Inputs::SecurityIncidentResponse
  #
  # Returns successful_remediations and failed_remediations, both arrays of the names of the remediations.
  def run_remediations(user, response, user_template_data)
    failed_remediations = []
    successful_remediations = []

    remediations = remediations_for_response(response)

    add_error_for_missing_or_staff_users!(user, remediations.keys)

    remediations.each do |type, remediation_data|
      # Don't list something like { reset_password: false } as an attempted remediation.
      next unless remediation_data.present?

      notifying_or_staffnoting = [:notify, :staffnote].include?(type)

      # If the user is not found or is a staff member, return all remediations as failed
      # unless we're notifying or writing a staffnote for a staff member, which are allowed.
      if user.nil? || (user&.employee? && !notifying_or_staffnoting)
        failed_remediations.push(type)
        next
      end

      # Don't notify or write staffnotes if remediations have failed
      if notifying_or_staffnoting && failed_remediations.present?
        failed_remediations.push(type)
        next
      end

      if perform_remediation(user, type, remediation_data, user_template_data)
        successful_remediations.push(type)
      else
        failed_remediations.push(type)
      end
    end

    [successful_remediations, failed_remediations]
  end

  def add_error_for_missing_or_staff_users!(user, remediations)
    if user.nil?
      errors << "Account not found."
    end

    if user&.employee? && (remediations - [:notify, :staffnote]).present?
      errors << "When SIRE is acting on a GitHub employee it can only do the notify and/or staffnote remediations"
    end
  end

  # Private: Gathers the remediations from the response as it may include other data
  # and puts the notify and staffnote remediations at the end so that we can not do them
  # if other remediations failed.
  def remediations_for_response(response)
    remediations = response.except(:notify, :staffnote, :user_id, :users)
    remediations[:notify] = response[:notify] if response[:notify].present?
    remediations[:staffnote] = response[:staffnote] if response[:staffnote].present?
    remediations
  end

  def perform_remediation(user, type, remediation_data, user_template_data)
    case type
    when :delete_issues
      delete_issues(user, remediation_data)
    when :delete_issue_comments
      delete_issue_comments(user, remediation_data)
    when :notify
      notify_user(user, remediation_data, user_template_data)
    when :remove_repository_recommendations
      remove_repository_recommendations(user, remediation_data)
    when :remove_repository_stars
      remove_repository_stars(user, remediation_data)
    when :reset_password
      reset_password(user)
    when :revoke_oauth_authorizations
      revoke_oauth_authorizations(user, remediation_data)
    when :revoke_oauth_tokens
      revoke_oauth_tokens(user, remediation_data)
    when :staffnote
      write_staffnote(user, remediation_data)
    when :suspend
      # remediation_data is the reason
      user.suspend(remediation_data, actor: actor)
    when :set_screening_status
      set_screening_status(user, remediation_data)
    when :sdn_manual_screening
      sdn_manual_screening(user)
    when :sdn_suspend
      # remediation_data is the reason string
      sdn_suspend_account(user, remediation_data)
    when :sdn_unsuspend
      # remediation_data is the reason string
      sdn_unsuspend_account(user, remediation_data)
    else
      false
    end
  end

  def write_staffnote(user, staffnote_text)
    return false unless staffnote_text.present?

    StaffNote.create(user: actor, notable: user, note: staffnote_text)

    true
  end

  def delete_issues(user, all_issue_ids)
    type = :delete_issues
    safe_perform_remediation(user, type, ActiveRecord::ActiveRecordError) do
      found_issue_ids = []

      # querying issues to see which ones exist and belong to provided user
      with_read do
        all_issue_ids.each_slice(50) do |issue_ids|
          Issue.throttle do
            ids = Issue.where(id: issue_ids, user_id: user.id).pluck(:id)
            found_issue_ids.concat(ids)
          end
        end
      end


      # invoke background job to delete issues in batches
      Issues::BatchDeleteIssuesJob.perform_later(issue_ids: found_issue_ids, actor_id: @actor.id)
      not_found_issues = all_issue_ids - found_issue_ids

      if not_found_issues.present?
        errors << "#{type}: Did not find issues with ids: #{not_found_issues.join(", ")} for user #{user.login}."
        return false if not_found_issues.size == all_issue_ids.size
      end

      # Deletions will happen in the background, so we can't check for success.
      true
    end
  end

  def delete_issue_comments(user, all_issue_comment_ids)
    type = :delete_issue_comments
    safe_perform_remediation(user, type, ActiveRecord::ActiveRecordError) do
      found_issue_comment_ids = []

      # querying issue_comments to see which ones exist and belong to provided user
      with_read do
        all_issue_comment_ids.each_slice(50) do |issue_comment_ids|
          IssueComment.throttle do
            ids = IssueComment.where(id: issue_comment_ids, user_id: user.id).pluck(:id)
            found_issue_comment_ids.concat(ids)
          end
        end
      end

      # invoke background job to delete issue comments in batches
      Issues::BatchDeleteIssueCommentsJob.perform_later(issue_comment_ids: found_issue_comment_ids, actor_id: @actor.id)
      not_found_issue_comments = all_issue_comment_ids - found_issue_comment_ids

      if not_found_issue_comments.present?
        errors << "#{type}: Did not find issue comments with ids: #{not_found_issue_comments.join(", ")} for user #{user.login}."
        return false if not_found_issue_comments.size == all_issue_comment_ids.size
      end

      # Deletions will happen in the background, so we can't check for success.
      true
    end
  end

  def notify_user(user, notify_data, user_template_data)
    return false unless notify_data.present?

    notifier = GitHub::SendSecurityIncidentNotification.new(
      from: notify_data[:from],
      subject: notify_data[:subject],
      template: notify_data[:template],
    )
    template_data = { login: user.login }
    Array(user_template_data || notify_data[:template_data]).each do |data|
      template_data[data[:key].to_sym] = data[:value]
    end
    notifier.perform_for_user(user, template_data)

    true
  end

  def safe_perform_remediation(user, type, *error_classes)
    begin
      yield
    rescue *error_classes => e
      Failbot.report(e, user_global_relay_id: user.global_relay_id, remediation_type: type)
      false
    end
  end

  def set_screening_status(user, screening_data)
    if !AccountScreeningProfile::VALID_SDN_STATUSES.include?(screening_data[:status].to_sym)
      errors << "Trade screening status '#{screening_data[:status]}' is not a valid screening status"
      return false
    end

    trade_screening_record = user.trade_screening_record(ignore_linked_record: true)
    update_screening_status_hash = {
      msft_trade_screening_status: screening_data[:status],
      metadata: trade_screening_record.metadata.merge({ "status_reason": screening_data[:reason] }),
    }

    safe_perform_remediation(user, :set_screening_status, ActiveRecord::ActiveRecordError) do
      trade_screening_record.update(update_screening_status_hash)
    end
  end

  def sdn_manual_screening(user)
    safe_perform_remediation(user, :sdn_manual_screening, ActiveRecord::ActiveRecordError) do
      user.perform_live_sdn_screening(force: true)

      # perform_live_sdn_screening will return false if the user receives a restricted screening status
      # so we ignore the response and return true instead
      true
    end
  end

  def sdn_suspend_account(user, reason)
    if user.sdn_suspended?
      errors << "User is already SDN suspended"
      return false
    end

    user.sdn_suspend(staff_user: actor, reason: reason)
  end

  def sdn_unsuspend_account(user, reason)
    if !user.sdn_suspended?
      errors << "User is not SDN suspended"
      return false
    end

    user.sdn_unsuspend(staff_user: actor, reason: reason)
  end

  def reset_password(user)
    type = :reset_password
    safe_perform_remediation(user, type, ActiveRecord::ActiveRecordError) do
      user.set_random_password(
        actor: actor,
        send_notification: false,
      )
    end
  end

  def revoke_oauth_authorizations(user, application_ids)
    type = :revoke_oauth_authorizations
    safe_perform_remediation(user, type, ActiveRecord::ActiveRecordError) do
      valid_app_ids = user.oauth_authorizations.where(application_id: application_ids).pluck(:application_id)
      if valid_app_ids.blank?
        errors << "#{type}: User did not have any to revoke."
        return false if valid_app_ids.blank?
      end
      user.revoke_oauth_tokens_for_oauth_apps(
        valid_app_ids,
        should_throttle: true,
      )
      true
    end
  end

  def revoke_oauth_tokens(user, token_ids)
    type = :revoke_oauth_tokens
    safe_perform_remediation(user, type, ActiveRecord::ActiveRecordError) do
      valid_token_ids = user.oauth_accesses.where(id: token_ids).pluck(:id)
      if valid_token_ids.blank?
        errors << "#{type}: User did not have any to revoke."
        return false
      end
      user.revoke_specific_oauth_tokens(
        valid_token_ids,
        should_throttle: true,
      )
      true
    end
  end

  def remove_repository_recommendations(user, all_repository_ids)
    type = :remove_repository_recommendations
    safe_perform_remediation(user, type, ActiveRecord::ActiveRecordError) do
      not_users_repos = []
      all_repository_ids.each_slice(50) do |repository_ids|
        Repository.throttle do
          owned_repositories = user.repositories.where(id: repository_ids)
          owned_repository_ids = owned_repositories.pluck(:id)
          not_users_repos = not_users_repos.concat(repository_ids - owned_repository_ids)

          RepositoryRecommendationOptOut.throttle do
            owned_repositories.each do |repository|
              repository.set_network_privilege(:hide_from_discovery, true)
            end
          end
        end
      end
      Stafftools::NetworkPrivilege.recalculate_trending_repos

      if not_users_repos.present?
        errors << "#{type}: User did not own these repositories: #{not_users_repos.join(", ")}."
        return false if not_users_repos.size == all_repository_ids.size
      end

      true
    end
  end

  def remove_repository_stars(user, all_repository_ids)
    type = :remove_repository_stars
    safe_perform_remediation(user, type, ActiveRecord::ActiveRecordError) do
      repos_with_stars = []
      all_repository_ids.each_slice(50) do |repository_ids|
        Repository.throttle do
          repositories = Repository.where(id: repository_ids)

          Star.throttle do
            repositories.each do |repository|
              if user.unstar(repository, actor: actor)
                repos_with_stars << repository.id
              end
            end
          end
        end
      end

      repos_without_stars = all_repository_ids - repos_with_stars

      if repos_without_stars.present?
        errors << "#{type}: User did not have stars for these repositories: #{repos_without_stars.join(", ")}."
        return false if repos_without_stars.size == all_repository_ids.size
      end

      true
    end
  end
end
