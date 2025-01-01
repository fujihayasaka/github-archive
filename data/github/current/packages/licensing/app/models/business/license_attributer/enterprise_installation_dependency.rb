# typed: strict
# frozen_string_literal: true

module Business::LicenseAttributer::EnterpriseInstallationDependency
  extend T::Helpers

  extend ActiveSupport::Concern

  include GitHub::Memoizer

  requires_ancestor { Business::LicenseAttributer }

  sig { returns(T::Array[String]) }
  memoize def unidentified_enterprise_user_accounts_logins
    GitHub.tracer.in_span("Business::LicenseAttributer::EnterpriseInstallationDependency#unidentified_enterprise_user_accounts_logins", kind: :internal) do
      BusinessUserAccount.where(id: unidentified_business_user_account_ids).select(:login).in_batches.each_with_object([]) do |accounts, rows|
        accounts.pluck(:login).each do |login|
          rows << login
        end
      end
    end
  end

  # Enterprise server users without a linked user or email address
  sig { returns(T::Array[Integer]) }
  memoize def unidentified_business_user_account_ids
    GitHub.tracer.in_span("Business::LicenseAttributer::EnterpriseInstallationDependency#unidentified_business_user_account_ids", kind: :internal) do
      # enterprise server users without a linked user or email address
      business.user_accounts.where(user_id: nil).roles([:server_member, :server_admin]).exclude_unaffiliated_role.pluck(:id) -
        business.user_accounts_with_only_emails.pluck(:id)
    end
  end

  sig do
    returns({
      server_instances: T::Array[{
        server_id: Integer,
        hostname: String,
        last_sync: {
          date: DateTime,
          status: T.nilable(String),
          error: String,
        }
      }]
    })
  end
  def enterprise_installation_sync_status
    sync_job_statuses = []
    ActiveRecord::Base.connected_to(role: :reading) do
      enterprise_installations = EnterpriseInstallation.select(:id, :host_name, :server_id).where(owner_id: business.id)
      break sync_job_statuses if enterprise_installations.empty?

      sql = Arel.sql <<-SQL
      SELECT a.enterprise_installation_id, a.updated_at, a.sync_state
      FROM enterprise_installation_user_accounts_uploads a
      INNER JOIN
      (
        SELECT enterprise_installation_id, max(updated_at) as latest
        FROM enterprise_installation_user_accounts_uploads
        GROUP BY enterprise_installation_id
      ) b
      ON a.enterprise_installation_id = b.enterprise_installation_id AND a.updated_at = b.latest
      SQL

      results = EnterpriseInstallationUserAccountsUpload.connection.select_rows(sql)
      break sync_job_statuses if results.empty?

      enterprise_installations.each do |n|
        eid_upload = results.select { |m| m if m.first.eql? n.id }.flatten
        next if eid_upload.empty?

        sync_job_statuses << {
          server_id: n.server_id,
          hostname: n.host_name,
          last_sync: {
            date: eid_upload[1].to_datetime,
            status: get_sync_state(eid_upload[2]),
            error: "",
          },
        }
      end
    end

    {
      server_instances: sync_job_statuses,
    }
  end

  sig { params(sync_state_enum: Integer).returns(T.nilable(String)) }
  def get_sync_state(sync_state_enum)
    case sync_state_enum
    when 0
      "pending"
    when 1
      "success"
    when 2
      "failure"
    else
      nil
    end
  end

  # Return a hash of email addresses to a hash of arrays of hostname:id and email entries for all instances
  # for the BusinessUser associated with that email address.
  sig do
    params(email_addresses: T::Set[String], slice_size: Integer)
    .returns(T::Hash[T.untyped, T.nilable(BusinessUserAccount)])
  end
  def get_enterprise_server_users_per_email(email_addresses, slice_size: 1_000)
    return {} if email_addresses.blank?

    # Because only the first primary email address is used to identify the business user, we need to get
    # the business user and then pull all the hostnames and users IDs for that business user on all instances,
    # regardless of the email address.
    account_emails = []
    enterprise_installations_business_user_accounts.keys.each_slice(slice_size) do |slice|
      email_addresses.each_slice(slice_size) do |email_slice|
        account_emails.concat(
          EnterpriseInstallationUserAccountEmail.where(
            enterprise_installation_user_account_id: slice,
            email: email_slice
          ).to_a
        )
      end
    end

    enterprise_users = account_emails.map do |e|
      [e.email.downcase, enterprise_installations_business_user_accounts[e.enterprise_installation_user_account_id]]
    end.to_h

    enterprise_users
  end

  # Return a hash of email addresses to a hash of arrays of hostname:id and email entries for all instances
  # for the BusinessUser associated with that email address.
  sig do
    params(enterprise_users: T::Hash[T.untyped, T.nilable(BusinessUserAccount)])
    .returns(
      T::Hash[
        String,
        {
          instances: String,
          emails: T::Array[String],
          enterprise_server_advanced_security_user_ids: T::Set[String],
          enterprise_server_code_security_user_ids: T::Set[String],
          enterprise_server_secret_protection_user_ids: T::Set[String]
        }
      ]
    )
  end
  def get_enterprise_server_hostnames_emails_by_email(enterprise_users)
    return {} if enterprise_users.blank?

    email_map = {}
    enterprise_users.each do |email, user|
      primary_emails = T.must(user).enterprise_installation_user_account_emails.primary.pluck(:email).uniq
      T.must(user).enterprise_installation_user_accounts.each do |ei_user_account|
        add_enterprise_user_account!(
          email_map[email] ||= {},
          ei_user_account,
          enterprise_installations: business_enterprise_installations,
          primary_emails: primary_emails,
        )
      end
    end

    email_map
  end

  sig do
    params(
      dest: T::Hash[Symbol, T.untyped],
      ei_user_account: T.untyped,
      enterprise_installations: T.untyped,
      primary_emails: T.untyped
    ).void
  end
  def add_enterprise_user_account!(dest, ei_user_account, enterprise_installations:, primary_emails:)
    host_name = enterprise_installations[ei_user_account.enterprise_installation_id]

    remote_user_id = ei_user_account.remote_user_id
    remote_role = ei_user_account.site_admin? ? "Owner" : "Member"

    instance = "#{remote_user_id}:#{host_name}:#{remote_role}"

    dest[:instances] ||= []
    dest[:instances] << instance
    dest[:emails] = primary_emails unless primary_emails.nil?
    dest[:enterprise_server_advanced_security_user_ids] ||= Set.new
    dest[:enterprise_server_advanced_security_user_ids] << "#{remote_user_id}:#{host_name}" if ei_user_account.using_advanced_security
    dest[:enterprise_server_code_security_user_ids] ||= Set.new
    dest[:enterprise_server_code_security_user_ids] << "#{remote_user_id}:#{host_name}" if ei_user_account.using_code_security
    dest[:enterprise_server_secret_protection_user_ids] ||= Set.new
    dest[:enterprise_server_secret_protection_user_ids] << "#{remote_user_id}:#{host_name}" if ei_user_account.using_secret_protection
  end

  # Return a hash of user_ids to a hash of arrays of hostname:id and email entries for all instances
  # for the BusinessUser associated with that login
  sig do
    params(user_ids: T::Set[Integer])
    .returns(
      T::Hash[
        Integer,
        {
          instances: String,
          emails: T::Array[String],
          enterprise_server_advanced_security_user_ids: T::Set[String],
          enterprise_server_code_security_user_ids: T::Set[String],
          enterprise_server_secret_protection_user_ids: T::Set[String]
        }
      ]
    )
  end
  def enterprise_server_hostnames_emails_by_user_id(user_ids)
    return {} if user_ids.blank?

    accounts = {}
    ei_user_accounts = EnterpriseInstallationUserAccount.includes(:business_user_account, :emails).
      where(enterprise_installation_id: business_enterprise_installations.keys).
      where("business_user_account.user_id": user_ids)

    ei_user_accounts.each do |ei_user_acc|
      primary_emails = ei_user_acc.emails.select(&:primary).map(&:email).uniq

      host_name = business_enterprise_installations[ei_user_acc.enterprise_installation_id]
      add_enterprise_user_account!(
        accounts[ei_user_acc.business_user_account.user_id] ||= {},
        ei_user_acc,
        enterprise_installations: business_enterprise_installations,
        primary_emails: primary_emails,
      )
    end

    accounts
  end

  sig { returns(T::Hash[T.nilable(Integer), T.nilable(BusinessUserAccount)]) }
  memoize def enterprise_installations_business_user_accounts
    buas = BusinessUserAccount.where(business_id: business.id).map { |bua| [bua.id, bua] }.to_h
    EnterpriseInstallationUserAccount.where(
      enterprise_installation_id: business_enterprise_installations.keys
    ).pluck(:id, :business_user_account_id).map { |id, business_user_account_id| [id, buas[business_user_account_id]] }.reject { |_k, v| v.nil? }.to_h
  end

  # Return a hash of logins to a hash of arrays of hostname:id entries for all instances
  # for the BusinessUserAccount associated with the logins.
  sig do
    params(logins: T::Array[String])
    .returns(
      T::Hash[
        String,
        {
          instances: T::Array[String],
          emails: T::Array[String],
          enterprise_server_advanced_security_user_ids: T::Set[String]
        }
      ]
    )
  end
  def enterprise_server_hostnames_by_logins(logins: [])
    logins = logins.reject { |login| login.blank? }
    return {} if logins.blank?

    buas = BusinessUserAccount.joins(:enterprise_installation_user_accounts)
      .where(
        business_id: business.id,
        login: logins,
        enterprise_installation_user_accounts: { enterprise_installation_id: business_enterprise_installations.keys }
      )

    accounts = {}
    buas.each do |bua|
      bua.enterprise_installation_user_accounts.each do |ei_user_account|
        add_enterprise_user_account!(
          accounts[bua.display_login] ||= {},
          ei_user_account,
          enterprise_installations: business_enterprise_installations,
          primary_emails: nil,
        )
      end
    end
    accounts
  end

  sig { returns(T::Hash[Integer, String]) }
  memoize def business_enterprise_installations
    business.enterprise_installations.pluck(:id, :host_name).to_h
  end

  # Ensure the users are associated with this business
  sig { params(check_user_ids: T::Set[Integer]).returns(T::Set[Integer]) }
  def user_ids_from_business(check_user_ids)
    check_user_ids & user_ids
  end

  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def business_enterprise_installation_user_ids(skip_cache: false)
    return @business_enterprise_installation_user_ids if defined?(@business_enterprise_installation_user_ids)

    @business_enterprise_installation_user_ids = T.let(
      business.license_attributer_cache.ids("enterprise_installation_user_ids", skip_cache: skip_cache) do
        business.enterprise_installation_user_ids
      end,
      T.nilable(T::Array[Integer])
    )
  end

  sig { params(skip_cache: T.nilable(T::Boolean)).returns(T.nilable(T::Array[Integer])) }
  def suspended_enterprise_installation_user_ids(skip_cache: false)
    return @suspended_enterprise_installation_user_ids if defined?(@suspended_enterprise_installation_user_ids)

    @suspended_enterprise_installation_user_ids = T.let(
      business.license_attributer_cache.ids("suspended_enterprise_installation_user_ids", skip_cache: skip_cache) do
        business.user_accounts.
          joins(:enterprise_installation_user_accounts).
          where(user_id: business_enterprise_installation_user_ids).
          where.not('enterprise_installation_user_accounts.suspended_at': nil).
          distinct.
          pluck(:user_id)
      end,
      T.nilable(T::Array[Integer]))
  end
end
