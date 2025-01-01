# typed: true
# frozen_string_literal: true

class Licensing::GenerateMeteredServerLicenseJob < ApplicationJob
  queue_as :licensing

  retry_on_dirty_exit

  before_enqueue do |job|
    license_id = job.arguments.first
    with_write { Licensing::JobStatus.create(id: self.class.job_id(license_id)) }
  end

  sig { returns(String) }
  def self.prefix
    "metered-server-license"
  end

  sig { params(license_id: Integer).returns(String) }
  def self.job_id(license_id)
    "#{prefix}-#{license_id}"
  end

  sig { params(license_id: Integer).returns(T.nilable(JobStatus)) }
  def self.status(license_id)
    Licensing::JobStatus.find(self.job_id(license_id))
  end

  sig { params(license_id: Integer).void }
  def perform(license_id)
    return unless metered_server_license = Licensing::GhesLicense.find_by(id: license_id)
    return unless job_status = self.class.status(license_id)

    job_status.track do
      with_write do
        metered_server_license.generate_server_license_key
      end
    end
  end
end
