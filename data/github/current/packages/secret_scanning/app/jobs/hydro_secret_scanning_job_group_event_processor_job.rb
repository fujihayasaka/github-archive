# typed: true
# frozen_string_literal: true

class HydroSecretScanningJobGroupEventProcessorJob < HydroMessageJob
  include SecretScanning::Features::FeatureFlagHelper
  extend T::Sig

  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :hydro_secret_scanning_job_group_event_processor

  retry_on_dirty_exit
  retry_on *Resiliency::Response::UnavailableExceptions
  retry_on Freno::Throttler::Error, Freno::Error, Freno::Throttler::WaitedTooLong

  # This job sends emails for completed dry run job group events and initial org/enterprise enablement backfills.
  def perform
    case message[:group_type]
    when :GROUP_TYPE_DRY_RUN
      handle_dry_run_message(message)
    when :GROUP_TYPE_BACKFILL
      handle_backfill_message(message)
    else
      # do nothing
    end
  end

  # Handle backfill job group events, specifically org/enterprise enablement.
  sig { params(message: T::Hash[Symbol, T.untyped]).void }
  def handle_backfill_message(message)
    tss_client = GitHub::TokenScanning::Service::Client.new(actor)
    return unless is_completed_org_or_enterprise_enablement?(message)

    options = {}
    options[:job_group_id] = message[:group_id]
    summary_response = tss_client.get_job_group_summary(options)
    if summary_response.nil?
      Failbot.report(StandardError.new("couldn't query secret scanning job groups API"))
      return
    end
    if summary_response.error.present?
      if summary_response.error.code == :not_found
        Failbot.report(StandardError.new("job group could not be found"), job_group_id: message[:group_id])
        return
      end

      Failbot.report(StandardError.new("unexpected error when querying secret scanning job groups API"), job_group_id: message[:group_id], error: summary_response.error)
      return
    end

    if summary_response.data&.total_token_count == 0
      # Send no results email to org/enterprise admin if no secrets were found across all repos in the backfill
      send_no_secrets_found_email(message)
    else
      # total_token_count > 0, so secrets were found
      send_secrets_found_email(message, summary_response.data)
    end
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
  def is_completed_org_or_enterprise_enablement?(message)
    message[:group_status] == :GROUP_STATUS_COMPLETED && message[:scope].in?([:ORGANIZATION_SCOPE, :BUSINESS_SCOPE])
  end

  class GetOwnerAndUsersToNotifyError < StandardError
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).returns(T::Array[T.untyped]) }
  def get_owner_and_users_to_notify(message)
    users_to_notify = T.let(nil, T.untyped)

    GitHub::CurrentTenant.unscope do
      if message[:scope] == :ORGANIZATION_SCOPE
        owner = User.find_by(id: message[:owner_id])
        if owner.nil?
          raise GetOwnerAndUsersToNotifyError.new("cannot find owner")
        end
        business = GitHub.multi_tenant_enterprise? ? owner.business : nil
        GitHub::CurrentTenant.set(business) do
          users_to_notify = SecretScanning::Features::Org::TokenScanning.new(owner).get_admins_to_notify
        end
      elsif message[:scope] == :BUSINESS_SCOPE
        owner = Business.find_by(id: message[:owner_id])
        if owner.nil?
          raise GetOwnerAndUsersToNotifyError.new("cannot find owner")
        end
        business = owner
        GitHub::CurrentTenant.set(business) do
          users_to_notify = SecretScanning::Features::Business::TokenScanning.new(owner).get_admins_to_notify
        end
      else
        raise GetOwnerAndUsersToNotifyError.new("invalid scope. shouldn't get here!")
      end

      # Remove users who don't have the user-level emails setting turned on
      users_to_notify = users_to_notify.select do |user|
        settings = GitHub.newsies.settings(user)
        next settings.success? && settings.subscribed_email?
      end

      [owner, business, users_to_notify]
    end
  end

  sig { params(message: T::Hash[Symbol, T.untyped]).void }
  def send_no_secrets_found_email(message)
    begin
      owner, business, users_to_notify = get_owner_and_users_to_notify(message)
    rescue GetOwnerAndUsersToNotifyError => err
      Failbot.report(GetOwnerAndUsersToNotifyError.new("can't find users to notify for owner"), job_group_id: message[:group_id], scope: message[:scope], owner_id: message[:owner_id], msg: err.message)
      return
    end

    GitHub::CurrentTenant.set(business) do
      SecretScanningMailer.no_secrets_found_for_initial_org_or_enterprise_backfill(users_to_notify, owner, message[:group_id]).deliver_later
    end

    GitHub.logger.info("Sent initial backfill no secrets found email", {
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.notifications.owner.id" => message[:owner_id],
      "gh.notifications.scope" => message[:scope],
      "gh.notifications.job_group_id" => message[:group_id]
    })
  end

  sig { params(message: T::Hash[Symbol, T.untyped], summary: GitHub::Proto::SecretScanning::Api::V1::JobGroupSummaryResponse).void }
  def send_secrets_found_email(message, summary)
    begin
      owner, business, users_to_notify = get_owner_and_users_to_notify(message)
    rescue GetOwnerAndUsersToNotifyError => err
      Failbot.report(GetOwnerAndUsersToNotifyError.new("can't find users to notify for owner"), job_group_id: message[:group_id], scope: message[:scope], owner_id: message[:owner_id], msg: err.message)
      return
    end

    GitHub::CurrentTenant.set(business) do
      SecretScanningMailer.secrets_found_for_initial_org_or_enterprise_backfill(users_to_notify, owner, message[:group_id], summary.repos_scanned_count, summary.total_token_count).deliver_later
    end

    GitHub.logger.info("Sent initial backfill secrets found email", {
      "code.namespace" => self.class.name,
      "code.function" => "perform",
      "gh.notifications.owner.id" => message[:owner_id],
      "gh.notifications.scope" => message[:scope],
      "gh.notifications.job_group_id" => message[:group_id]
    })
  end

  def handle_dry_run_message(message)
    case message[:event_type]
    when :EVENT_TYPE_DONE
      handle_dry_run_done(message)
    end
  end

  def handle_dry_run_done(message)
    case message[:group_status]
    when :GROUP_STATUS_COMPLETED, :GROUP_STATUS_TOO_MANY_RESULTS
      if message[:scope].in?([:ORGANIZATION_SCOPE, :BUSINESS_SCOPE])
        send_completion_email(message)
      end
    end
  end

  def send_completion_email(message)
    options = {}
    owner_scope = message[:scope]
    proto_dry_run_scope = {}
    proto_dry_run_scope[:owner_id] = message[:owner_id]
    proto_dry_run_scope[:owner_scope] = owner_scope
    proto_dry_run_scope[:job_group_id] = message[:group_id]
    options[:dry_run_scope] = proto_dry_run_scope

    owner = T.let(nil, T.nilable(T.any(Organization, Business)))
    business = T.let(nil, T.nilable(Business))
    cp_options = {}

    GitHub::CurrentTenant.unscope do
      case owner_scope
      when :ORGANIZATION_SCOPE
        cp_options[:org_selector] = {
          owner_id: message[:owner_id]
        }
        owner = Organization.find_by(id: message[:owner_id])
        business = GitHub.multi_tenant_enterprise? ? owner&.business : nil
      when :BUSINESS_SCOPE
        cp_options[:business_selector] = {
          business_id: message[:owner_id]
        }
        owner = Business.find_by(id: message[:owner_id])
        business = owner
      end

      if owner.nil?
        GitHub.logger.info("Owner not found", {
          "code.namespace" => self.class.name,
          "code.function" => "perform",
        })

        return
      end
    end

    GitHub::CurrentTenant.set(business) do
      tss_client = GitHub::TokenScanning::Service::Client.new(actor)
      dry_run_metadata = tss_client.dry_run_metadata_for_pattern(options)

      #pattern will not be found if a user deletes the pattern before this point,
      #in this case, return and don't send an email
      if dry_run_metadata&.error&.code == :not_found
        return
      end

      cpid = dry_run_metadata&.data&.custom_pattern_id
      cp_options[:id] = cpid

      custom_pattern_response = tss_client.get_custom_pattern(cp_options)
      custom_pattern = custom_pattern_response&.data&.custom_pattern
      serializable_custom_pattern = {
        id: custom_pattern&.id,
        name: custom_pattern&.display_name
      }

      created_by = User.find_by(id: custom_pattern&.created_by_id)

      if created_by.nil?
        GitHub.logger.info("Custom pattern author not found", {
          "code.namespace" => self.class.name,
          "code.function" => "perform",
          "gh.notifications.pattern_id" => custom_pattern&.id,
          "gh.notifications.owner.id" => owner&.id,
          "gh.notifications.scope" => owner_scope.downcase,
          "gh.notifications.dry_run_status" => message[:group_status]
        })

        return
      end

      SecretScanningMailer.custom_pattern_dry_run_scan_summary(owner, owner_scope.downcase, serializable_custom_pattern, created_by, dry_run_metadata&.data&.total_result_count).deliver_later

      GitHub.logger.info("JobGroupEvent message processed", {
        "code.namespace" => self.class.name,
        "code.function" => "perform",
        "gh.notifications.pattern_id" => custom_pattern&.id,
        "gh.notifications.owner.id" => owner&.id,
        "gh.notifications.scope" => owner_scope.downcase,
        "gh.notifications.dry_run_status" => message[:group_status]
      })
    end
  end

  # Maps to the 'sender' object in the event payload. For 'alert location created' events, the sender is github.
  def actor
    return @actor if defined? @actor

    @actor = with_read { User.find_by_login("github") }
  end
end
