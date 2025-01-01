# typed: true
# frozen_string_literal: true

# Syncs user accounts sourced from an Enterprise Server installation with
# an EnterpriseInstallation stored in Enterprise Cloud.
#
# Expects the following arguments in this order:
#
# business -      Required. The Business for which the sync is happening.
# installation -  Optional. An existing EnterpriseInstallation for which the sync
#                 is being initiated.
# upload_id -     An Integer representing the ID of an
#                 EnterpriseInstallationUserAccountsUpload pointing to a file
#                 containing the data to be synced.
# actor -         The User that uploaded the user accounts file.
class SyncEnterpriseServerUserAccountsJob < ApplicationJob
  queue_as :sync_enterprise_server_user_accounts

  attr_reader :business, :installation, :upload_id, :status, :actor

  resolve_tenant_context do |business|
    business
  end

  before_enqueue do |job|
    business = job.arguments[0]
    installation = job.arguments[1]
    upload_id = job.arguments[2]
    actor = job.arguments[3]
    with_write do
      status = JobStatus.create(id: SyncEnterpriseServerUserAccountsJob.job_id(business, upload_id))
    end
  end

  def self.job_id(business, upload_id)
    "sync-enterprise-server-user-accounts-#{business.id}-#{upload_id}"
  end

  def self.status(business, upload_id)
    JobStatus.find(SyncEnterpriseServerUserAccountsJob.job_id(business, upload_id))
  end

  def self.status!(business, upload_id)
    JobStatus.find!(SyncEnterpriseServerUserAccountsJob.job_id(business, upload_id))
  end

  def initialize(*arguments)
    @business = arguments[0]
    @installation = arguments[1]
    @upload_id = arguments[2]
    @actor = arguments[3]

    super(*T.unsafe(arguments))
  end

  def perform(business, installation, upload_id, actor)
    raise ArgumentError, "business cannot be nil" if business.nil?
    raise ArgumentError, "upload_id cannot be nil" if upload_id.nil?
    raise ArgumentError, "actor cannot be nil" if actor.nil?

    @business = business
    @installation = installation
    @upload_id = upload_id
    @actor = actor
    @status = SyncEnterpriseServerUserAccountsJob.status!(business, upload_id)

    status.track do
      importer = EnterpriseInstallationUserAccountsImporter.new \
        business: business,
        installation: installation,
        upload_id: upload_id,
        actor: actor
      with_write { importer.synchronize_user_accounts_data! }
    end
  end
end
