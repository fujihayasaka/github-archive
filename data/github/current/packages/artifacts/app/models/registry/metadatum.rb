# typed: true
# frozen_string_literal: true

class Registry::Metadatum < ApplicationRecord::Domain::Packages # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  self.table_name = :registry_package_metadata
  KEYS = {
    DOCKER_IMAGE_MANIFEST: "docker:schema:v2:image:manifest",
    INSTALLATION_COMMAND: "InstallationCommand",
    README: "Readme",
    SUMMARY: "Summary",
  }
  NON_SERIALIZED_KEYS = [KEYS[:SUMMARY], KEYS[:DOCKER_IMAGE_MANIFEST], KEYS[:README], KEYS[:INSTALLATION_COMMAND]]

  include GitHub::Relay::GlobalIdentification

  attribute :value, UnconvertedStringFromBinary.new

  belongs_to :package_version

  validates :name, presence: true, uniqueness: { scope: :package_version_id, case_sensitive: false }
  validates :value, length: { maximum: 500 }, if: -> (r) { r.name == KEYS[:INSTALLATION_COMMAND] }

  before_save :truncate_value

  def self.summary
    self.get(KEYS[:SUMMARY])
  end

  def self.readme
    self.get(KEYS[:README])
  end

  def self.docker_manifest
    self.get(KEYS[:DOCKER_IMAGE_MANIFEST])
  end

  def self.installation_command
    self.get(KEYS[:INSTALLATION_COMMAND])
  end

  def self.get(metadatum_name)
    metadatum = where(name: metadatum_name).first
    # Content may come from arbitrary files, from web forms, etc., so the
    # encoding may not be UTF-8, but UTF-8 is required for GraphQL and web views.
    GitHub::Encoding.try_guess_and_transcode(metadatum&.value.to_s)
  end

  def self.set(metadatum_name, value)
    metadatum = where(name: metadatum_name).first
    metadatum ||= all.build(name: metadatum_name)
    metadatum.value = value
    metadatum.save
  end

  def self.serializeable
    where("name NOT IN (?)",  Registry::Metadatum::NON_SERIALIZED_KEYS)
  end

  def platform_type_name
    "Metadatum"
  end

  def truncate_value
    self.value = self.value.truncate_bytes(65535, omission: "")
  end
end
