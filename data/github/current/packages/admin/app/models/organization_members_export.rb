# typed: true
# frozen_string_literal: true

require "org"

class OrganizationMembersExport < ApplicationRecord::Domain::Users
  include GitHub::Validations

  belongs_to :actor, class_name: "User"
  belongs_to :subject, polymorphic: true

  validates :subject_type, presence: true
  validates :subject_id,   presence: true
  validates :actor_id,     presence: true
  validates :token,        presence: true
  validates :format,       presence: true, inclusion: { in: %w[json csv] }
  validates :phrase,       length: { maximum: 255 }, unicode3: true, allow_blank: true

  before_validation :set_default_format, on: :create
  before_validation :generate_token, on: :create
  after_create :increment_create_count
  after_commit :enqueue_process_export_results, on: :create
  before_destroy :delete_remote_file

  def human_filename
    "export-#{subject_label}-#{created_at.to_i}.#{format}"
  end

  # Public: The human readable name for the subject.
  #
  # Returns String.
  def subject_label
    case subject
    when User, Organization
      subject.login
    when Business
      subject.slug
    end
  end

  def filename
    "#{GitHub.filename_prefix_for_env}/#{token}.#{format}"
  end

  # Public: The content type for storing and downloading the organization members export.
  #
  # Returns String.
  def content_type
    case format
    when "json"
      "application/json"
    when "csv"
      "text/csv"
    end
  end

  def process
    GitHub.dogstats.time("organization_members_export_time", tags: ["action:process"]) do
      # Start the export process
      contents = Time.use_zone(T.must(actor).time_zone) do
        export = Org::BulkMembersExport.new(
          format: format,
          organization: subject,
          current_user: actor,
          for_site_admin: for_site_admin?
        )
        export.run
      end

      # The export is complete, store the results
      uploaded = store_results(contents)
    end
  end

  def storage
    GHECAdmin::Storage.make(filename, :org_members)
  end

  def exists?
    storage.exists?
  end

  def to_param
    token
  end

  private

  # Private: Store the export results remotely.
  #
  # contents - The String body of audit log export to store.
  #
  # Returns true if stored, false if not.
  def store_results(contents)
    storage.store(contents, content_type)
  end

  # Private: Process the export request in the background and report back to the
  # user when their export is ready for downloading.
  #
  # Returns nothing.
  def enqueue_process_export_results
    JobStatus.create(id: token)
    ProcessOrganizationMembersExportJob.perform_later(id)
  end

  # Private: The unique token for the audit log used to download the export.
  #
  # Returns String.
  def generate_token
    self.token = SecureRandom.uuid
  end

  def set_default_format
    self.format = "json" if self.format.blank?
  end

  def increment_create_count
    GitHub.dogstats.increment("organization_members_export", tags: ["action:create", "format:#{format}"])
  end

  # Private: Ensures the remote file is deleted when the record is deleted. There
  # is a change it has already been deleted due to the bucket lifecycle having
  # deleted the file already.
  #
  # Returns nothing.
  def delete_remote_file
    storage.cleanup
  end
end
