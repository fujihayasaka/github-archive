# frozen_string_literal: true

require "normal_yaml"

class AdvisoryPayload
  REQUIRED_KEYS = %w[
    cvss_v3
    cvss_v4
    cwe_ids
    description
    references
    severity
    source_code_location
    summary
    vulnerabilities
    withdrawn
  ].freeze

  include ActiveModel::Validations

  validates :data, class: Hash, normal: true, keys: REQUIRED_KEYS

  # In the default validation context (used for form submission), we want to
  # validate the format and structure of the data but allow the curation agent
  # to leave values blank.
  validates :summary, class: { is: String, allow_nil: true },
    length: { maximum: 255 }
  validates :description, class: { is: String, allow_nil: true },
    length: { maximum: 65_535 }
  validates :source_code_location, class: { is: String, allow_nil: true }
  validates :severity, inclusion: { in: AdvisoryDB.severities, allow_nil: true }
  validates :cvss_v3, class: { is: String, allow_nil: true },
    cvss_vector_string: true
  validates :cvss_v4, class: { is: String, allow_nil: true },
    cvss_vector_string: true
  validates :cwe_ids, class: Array
  validates :cwe_payloads, nested: true
  validates :references, class: Array
  validates :reference_payloads, nested: true
  validates :vulnerabilities, class: Hash
  validates :vulnerability_payloads, nested: true
  validates :withdrawn, inclusion: [true, false]
  validate :vulnerability_keys_must_be_sequential

  # In the validation context for publication, we need additional presence
  # validations for all of the required data.
  with_options on: :publication do
    validates :summary, :description, :severity, :vulnerabilities,
      presence: true
  end

  def self.valid?(data: {})
    new(data: data).valid?
  end

  def initialize(data: {})
    @data_given = data.deep_dup
  end

  def data
    return @data if defined? @data

    @data = normalize(@data_given.to_hash)
  end

  REQUIRED_KEYS.each do |key|
    define_method(key) do
      if data[key].is_a?(String) && data[key].respond_to?(:force_encoding) && data[key].encoding != Encoding::UTF_8
        data[key].force_encoding(Encoding::UTF_8)
      else
        data[key]
      end
    end
  end

  def reference_payloads
    return [] unless references.is_a?(Array)
    return @reference_payloads if defined? @reference_payloads

    @reference_payloads = references.map do |reference_data|
      ReferencePayload.new(reference_data)
    end
  end

  def vulnerability_payloads
    return {} unless vulnerabilities.is_a?(Hash)
    return @vulnerability_payloads if defined? @vulnerability_payloads

    @vulnerability_payloads = vulnerabilities.transform_values do |vulnerability_data|
      VulnerabilityPayload.new(vulnerability_data)
    end
  end

  def cwe_payloads
    return [] unless cwe_ids.is_a?(Array)
    return @cwe_payloads if defined? @cwe_payloads

    @cwe_payloads = cwe_ids.map do |cwe_id|
      CWEPayload.new(cwe_id)
    end
  end

  # This might look a little weird, but was taken from FeedEntry because the code logically belongs to this class.
  # It's not currently using the attributes on advisory_payload, but probably should be. Right now it is just a refactoring.
  def hydro_payload
    {
      description: data["description"] || "",
      severity: data.fetch("severity", :severity_unknown)&.upcase,
      references: data.fetch("references") { [] }.filter_map do |reference_data|
        next if reference_data.blank?

        {
          url: reference_data,
        }
      end,
      vulnerabilities: hydro_vulnerabilities,
      withdrawn: data["withdrawn"] == true,
      cwe_ids: data["cwe_ids"] || [],
      cvss_v3: data["cvss_v3"] || "",
      cvss_v4: data["cvss_v4"] || "",
    }
  end

  private

  def normalize(data)
    # Cast blank string attributes to nil.
    %w[
      cvss_v3
      cvss_v4
      description
      severity
      source_code_location
      summary
    ].each do |attribute|
      data[attribute] = data[attribute].presence
    end

    data[:description] = AdvisoryDBToolkit.normalize_description_line_endings(data[:description]) if data[:description].present?

    # Cast missing array attributes to [].
    %w[
      cwe_ids
      references
    ].each do |attribute|
      data[attribute] ||= []
    end

    # Cast missing vulnerabilities to {}.
    data["vulnerabilities"] ||= {}

    # Cast withdrawn to a boolean.
    data["withdrawn"] = ActiveModel::Type::Boolean.new.cast(data["withdrawn"]) || false

    # Cast a reference's blank URL to nil.
    data["references"].map!(&:presence)

    # Remove nil references.
    data["references"].compact!

    # Cast vulnerability indexes to integers.
    data["vulnerabilities"].transform_keys! do |key|
      /\A\d+\z/.match?(key.to_s) ? key.to_i : key
    end

    # Normalize each vulnerability.
    data["vulnerabilities"].each_value do |vulnerability_data|
      # Cast a vulnerability's blank string attributes to nil.
      %w[
        ecosystem
        package_name
        vulnerable_version_range
        first_patched_version
        fix_commits
      ].each do |attribute|
        vulnerability_data[attribute] = vulnerability_data[attribute].presence
      end

      vulnerability_data["fix_commits"] = (vulnerability_data["fix_commits"] || []).filter_map(&:presence)

      # Cast a vulnerability's withdrawn to a boolean.
      vulnerability_data["withdrawn"] = vulnerability_data["withdrawn"].present?
    end

    data
  end

  def vulnerability_keys_must_be_sequential
    return unless vulnerabilities.is_a?(Hash)

    actual_keys = vulnerabilities.keys
    expected_keys = (0...vulnerabilities.size).to_a

    return if actual_keys == expected_keys

    errors.add(:vulnerabilities, :nonsequential_keys, actual_keys: actual_keys, expected_keys: expected_keys)
  end

  # This might look a little weird living here, but this is specifically
  # for generating vulnerabilities lists from the vulnerabilities attribute in payload,
  # *not* for generating them from vulnerabilities that are stored in the DB as active records.
  def hydro_vulnerabilities
    vulnerabilities =
      data.fetch("vulnerabilities") { {} }.values.select do |vulnerability_data|
        # the FeedEntry hydro schema enforces valid ecosystem types, so we have to
        # sanitize the data prior to sending it out.

        vulnerability_data["withdrawn"] != true &&
          vulnerability_data["ecosystem"].present? &&
          AdvisoryDB.ecosystems.include?(vulnerability_data["ecosystem"].downcase)
      end

    vulnerabilities.map do |vulnerability_data|
      {
        package_ecosystem: vulnerability_data.fetch("ecosystem", "")&.upcase,
        package_name: vulnerability_data["package_name"] || "",
        vulnerable_version_range: vulnerability_data["vulnerable_version_range"] || "",
        first_patched_version: vulnerability_data["first_patched_version"] || "",
      }
    end
  end
end
