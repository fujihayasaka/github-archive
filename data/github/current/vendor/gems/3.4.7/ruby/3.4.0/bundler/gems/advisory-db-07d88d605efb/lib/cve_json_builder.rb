# frozen_string_literal: true

# rubocop:disable Naming/MethodName

require "cvss_suite"
require "json_schemer"
require "pathname"

# This class generates JSON that is ready to submit to MITRE.  This CVE JSON is custom-tailored for the GitHub AdvisoryDB use case,
# and should not be used elsewhere. Anything that can be hard-coded, is.  This class takes only the data that is different from CVE-to-CVE.
#
# Some notes about CVE JSON in general:
# - See what is actively being submitted and accepted by MITRE: https://github.com/CVEProject/cvelist/pulls?utf8=%E2%9C%93&q=is%3Apr+is%3Amerged+
# - Schema defining the 5.0 JSON:  https://github.com/CVEProject/cve-schema/blob/master/schema/v5.0/docs/CVE_JSON_5.0_bundled.json
# - Schema defining the 5.1.0 JSON:  https://github.com/CVEProject/cve-schema/blob/main/schema/docs/CVE_Record_Format_bundled.json
# - Tool we used before making our own JSON builder: https://vulnogram.github.io/#editor
# - Lots of data is repeated.  Simple example is that the reference `name` and `url` are typically the same (in our case, always the same)
#
# - There are inconsistent conventions for naming fields:
#   - Some are in snake case (eg: `vendor_data`)
#   - Some are in camel case (eg: `attackComplexity`)
#   - Some are in all caps (eg: `TITLE`).
#   - There can be inconsistent word boundaries, e.g. `problemtype` is one word for some reason
#
# Note:  When our CVE JSON Builder was created, the choice was made to match our method names to the camel case naming in the CVE schema.
# Therefore, some method names in this file do not follow Ruby conventions.  If we decide to at some point, we can change to the Ruby convention.
# If we do that, we should be sure to update other uses in our codebase, as well as database column names.  We should also remove the Rubocop disable
# for `Naming/MethodName` in this file.
#
# - The `cvss` field is very tricky
#   - It is full of redundant data, leaving many ways it could be built to be inconsistent with itself
#   - It supports multiple versions of CVSS (we only use 3.1 and 4.0)
#   - Since every part of CVSS can be built from the vector string, that is what this class requires
#   - Calculating the base score from the vector string is quite complex.  We use the cvss-suite gem for this purpose.
#
CVEJSONBuilder = Struct.new(
  :ghsa_id,
  :ghsl_id,
  :cve_id,
  :title,
  :description,
  :vendor_name,
  :product,
  :version_values,
  :problemtype_values,
  :confirm_reference,
  :misc_references,
  :cvss_vectorString,
  keyword_init: true, # allow initializing with keyword args
)

# Reopen the class rather than providing a block to Struct.new so that constant definitions are
# properly scoped to the class instead of being defined in the global namespace.
class CVEJSONBuilder
  # This default string is 0.0 NONE in "severity".
  # CVSS needs a default, since it is the basis for an entire part of the JSON.
  DEFAULT_CVSS_V3_VECTOR_STRING = "CVSS:3.1/AV:P/AC:H/PR:H/UI:R/S:U/C:N/I:N/A:N"
  DEFAULT_CVSS_V4_VECTOR_STRING = "CVSS:4.0/AV:N/AC:L/AT:N/PR:N/UI:N/VC:N/VI:N/VA:N/SC:N/SI:N/SA:N"

  include ActiveModel::Validations
  validates :ghsa_id, presence: true, ghsa_id: true
  validates :cve_id, presence: true, cve_id: true
  validates :title, length: { minimum: 2 }
  validates :description, length: { minimum: 2 }
  validates :vendor_name, length: { minimum: 2 }
  validates :product, presence: true
  validates :version_values, length: { minimum: 1 }
  validate :version_values_uniqueness

  def version_values_uniqueness
    if version_values && version_values.size != version_values.uniq.size
      errors.add(:version_values, "must be unique")
    end
  end

  validates :problemtype_values, length: { minimum: 1 }
  validate :confirm_reference_must_have_minimum_length

  def confirm_reference_must_have_minimum_length
    # Custom validation because the following does not work for validation pattern of 63 characters:
    #   "https://securitylab.github.com/advisories/GHSL-2022-004" (55 chars)
    minimum_length = ghsl_id.present? ? 55 : 63

    if confirm_reference.blank? || confirm_reference.length < minimum_length
      errors.add(:confirm_reference, "is too short (minimum is #{minimum_length} characters)")
    end
  end

  validates :cvss_vectorString, presence: true, cvss_vector_string: true
  validate :valid_for_mitre_submission?

  # Indicates a validation problem with the CVE review and/or advisory review or wrong adherence to the JSON schema
  def valid_for_mitre_submission?
    cve_review = CVEReview.find_by ghsa_id: ghsa_id

    unless cve_review&.notified? || cve_review&.open_update?
      message = cve_review ? "CVE Review must have state 'notified' (or 'open_update') in order to generate JSON but has state: #{cve_review.state}" : "No CVE Review found for ghsa_id: #{ghsa_id}"

      return errors.add(:base, :invalid, message: message)
    end

    advisory_review = AdvisoryReview.find_by ghsa_id: ghsa_id

    unless advisory_review&.repository_advisory_feed_entry? || ghsl_id.present?
      return errors.add(:base, :invalid, message: "Repository advisory #{ghsa_id} does not appear to have been published yet. Repository advisories must be published before CVEs can be submitted to MITRE.")
    end

    if (json_schema_errors = validate_json_schema)
      errors.add(:base, :invalid, message: "JSON schema is not valid: #{JSON.dump(json_schema_errors)}")
    end
  end

  # Return a JSON file that is ready to submit to MITRE.
  # The convention is to use pretty-formatted, non-compact JSON, since these are commonly human-read.
  def to_json(*)
    # Use four spaces for indent, which seems to be the main convention for MITRE JSON
    JSON.pretty_generate(to_h, indent: "    ")
  end

  # This makes sure that the JSON is valid, NOT that the data meets CVE requirements
  def validate_json_schema
    schema_file = AdvisoryDB::Features.enabled?("advisory_db_cvss_v4") ? "lib/cve/CVE_Record_Format_bundled.json" : "lib/cve/CVE_JSON_5.0_bundled.json"
    schema = Pathname.new(schema_file)
    schemer = JSONSchemer.schema(schema)
    errors = schemer.validate(JSON.parse(to_json)).map { |excluded| excluded.except("schema", "root_schema") }

    errors.empty? ? nil : errors
  end

  # Return a hash, ready to turn into JSON.
  # The ordering of the keys in the hash is the ordering that should be in the final JSON.
  # For 5.0 schema details, see https://github.com/CVEProject/cve-schema/blob/master/schema/v5.0/docs/CVE_JSON_5.0_bundled.json
  # For 5.1.0 schema details, see https://github.com/CVEProject/cve-schema/blob/main/schema/docs/CVE_Record_Format_bundled.json
  def to_h
    data_version = AdvisoryDB::Features.enabled?("advisory_db_cvss_v4") ? "5.1.0" : "5.0"

    {
      "dataType" => "CVE_RECORD",
      "dataVersion" => data_version,
      "cveMetadata" => {
        "cveId" => cve_id,
        "assignerOrgId" => AdvisoryDB.cve_api_org_id,
        "state" => "PUBLISHED",
      },
      "containers" => {
        "cna" => {
          "title" => title,
          "problemTypes" => problemtype_data,
          "metrics" => metrics,
          "references" => reference_data,
          "affected" => [
            {
              "vendor" => vendor_name,
              "product" => product,
              "versions" => version_data,
            },
          ],
          "providerMetadata" => {
            "orgId" => AdvisoryDB.cve_api_org_id,
          },
          "descriptions" => [
            {
              "lang" => "en",
              "value" => description,
            },
          ],
          "source" => {
            "advisory" => ghsa_id,
            "discovery" => "UNKNOWN",
          },
        },
      },
    }
  end

  private

  # Build and return a single item of the reference_data list
  def reference(url, type)
    {
      "name" => url,
      "tags" => ["x_refsource_#{type}"],
      "url" => url,
    }
  end

  def reference_data
    confirm_ref = reference(confirm_reference, "CONFIRM")

    sorted_and_filtered_misc_references =
      AdvisoryDBToolkit::ReferenceSorter.sorted_reference_list_for_cve(misc_references)

    misc_refs = sorted_and_filtered_misc_references.map do |ref|
      reference(ref, "MISC")
    end

    [confirm_ref] + misc_refs
  end

  def version_data
    version_values.map do |version_value|
      {
        "version" => version_value,
        "status" => "affected",
      }
    end
  end

  def problemtype_data
    problemtype_values.map do |problemtype_value|
      cwe_id = problemtype_value[/CWE-\d+/]

      {
        "descriptions" => [
          {
            "cweId" => cwe_id,
            "lang" => "en",
            "description" => problemtype_value,
            "type" => cwe_id ? "CWE" : nil,
          }.compact,
        ],
      }
    end
  end

  # This is needed so the below generation of the CVSS object works when a vector string is not yet defined
  def cvss_v3_vector_string_with_default
    self[:cvss_vectorString] || DEFAULT_CVSS_V3_VECTOR_STRING
  end

  # This is needed so the below generation of the CVSS object works when a vector string is not yet defined
  def cvss_v4_vector_string_with_default
    self[:cvss_vectorString] || DEFAULT_CVSS_V4_VECTOR_STRING
  end

  def generate_cvss_suite_instance
    CvssSuite.new(send(:"cvss_v#{cvss_key.match(/3|4/)}_vector_string_with_default"))
  end

  def cvss_builder
    @cvss_builder ||= generate_cvss_suite_instance
  end

  # This only works with version 3.1 and 4.0 vector strings.  Additionally, it only works with a subset
  # of the CVSS spec:
  # 3.1 spec:  https://www.first.org/cvss/v3.1/specification-document
  # 4.0 spec:  https://www.first.org/cvss/v4.0/specification-document
  # Specifically, this only supports CVSS vectors based on the "Base Metric Group."
  # It does not support Temporal, Environmental, or, in the case of version 4.0, Supplemental Metrics.
  # Temporal, Environmental, and Supplemental metrics are not commonly used, and most calculators do not
  # support them.
  #
  # Constructing this object is ridiculously complicated.  We could make this easier by extending
  # the cvss-suite gem to support generating this entire JSON object.  As it is, we can only use cvss-suite
  # to get the score and severity and to check validity.
  def cvss
    if AdvisoryDB::Features.enabled?("advisory_db_cvss_v4")
      if cvss_builder.instance_of?(CvssSuite::Cvss40)
        unless cvss_builder.valid?
          # We still want to return valid JSON even if the provided CVSS vector string has invalid metrics.
          # If this is the case, we will create it using DEFAULT_CVSS_V4_VECTOR_STRING.
          return {
            "attackVector" => "NETWORK",
            "attackComplexity" => "LOW",
            "attackRequirements" => "NONE",
            "privilegesRequired" => "NONE",
            "userInteraction" => "NONE",
            "vulnConfidentialityImpact" => "NONE",
            "vulnIntegrityImpact" => "NONE",
            "vulnAvailabilityImpact" => "NONE",
            "subConfidentialityImpact" => "NONE",
            "subIntegrityImpact" => "NONE",
            "subAvailabilityImpact" => "NONE",
            "baseScore" => 0.0,
            "baseSeverity" => "NONE",
            "vectorString" => DEFAULT_CVSS_V4_VECTOR_STRING,
            "version" => "4.0",
          }
        end

        {
          "attackVector" => attackVectorV4,
          "attackComplexity" => attackComplexity,
          "attackRequirements" => attackRequirements,
          "privilegesRequired" => privilegesRequired,
          "userInteraction" => userInteractionV4,
          "vulnConfidentialityImpact" => vulnConfidentialityImpact,
          "vulnIntegrityImpact" => vulnIntegrityImpact,
          "vulnAvailabilityImpact" => vulnAvailabilityImpact,
          "subConfidentialityImpact" => subConfidentialityImpact,
          "subIntegrityImpact" => subIntegrityImpact,
          "subAvailabilityImpact" => subAvailabilityImpact,
          "baseScore" => cvss_builder.overall_score,
          "baseSeverity" => cvss_builder.severity.upcase,
          "vectorString" => cvss_v4_vector_string_with_default,
          "version" => cvss_builder.version.to_s,
        }
      else
        unless cvss_builder.valid?
          # We still want to return valid JSON even if the provided CVSS vector string has invalid metrics.
          # If this is the case, we will create it using DEFAULT_CVSS_V3_VECTOR_STRING.
          return {
            "attackComplexity" => "HIGH",
            "attackVector" => "PHYSICAL",
            "availabilityImpact" => "NONE",
            "baseScore" => 0.0,
            "baseSeverity" => "NONE",
            "confidentialityImpact" => "NONE",
            "integrityImpact" => "NONE",
            "privilegesRequired" => "HIGH",
            "scope" => "UNCHANGED",
            "userInteraction" => "REQUIRED",
            "vectorString" => DEFAULT_CVSS_V3_VECTOR_STRING,
            "version" => "3.1",
          }
        end

        {
          "attackComplexity" => attackComplexity,
          "attackVector" => attackVectorV3,
          "availabilityImpact" => availabilityImpact,
          "baseScore" => cvss_builder.overall_score,
          "baseSeverity" => cvss_builder.severity.upcase,
          "confidentialityImpact" => confidentialityImpact,
          "integrityImpact" => integrityImpact,
          "privilegesRequired" => privilegesRequired,
          "scope" => scope,
          "userInteraction" => userInteractionV3,
          "vectorString" => cvss_v3_vector_string_with_default,
          "version" => cvss_builder.version.to_s,
        }
      end
    else
      unless cvss_builder.valid?
        # We still want to return valid JSON even if the provided CVSS vector string has invalid metrics.
        # If this is the case, we will create it using DEFAULT_CVSS_V3_VECTOR_STRING.
        return {
          "attackComplexity" => "HIGH",
          "attackVector" => "PHYSICAL",
          "availabilityImpact" => "NONE",
          "baseScore" => 0.0,
          "baseSeverity" => "NONE",
          "confidentialityImpact" => "NONE",
          "integrityImpact" => "NONE",
          "privilegesRequired" => "HIGH",
          "scope" => "UNCHANGED",
          "userInteraction" => "REQUIRED",
          "vectorString" => DEFAULT_CVSS_V3_VECTOR_STRING,
          "version" => "3.1",
        }
      end

      {
        "attackComplexity" => attackComplexity,
        "attackVector" => attackVectorV3,
        "availabilityImpact" => availabilityImpact,
        "baseScore" => cvss_builder.overall_score,
        "baseSeverity" => cvss_builder.severity.upcase,
        "confidentialityImpact" => confidentialityImpact,
        "integrityImpact" => integrityImpact,
        "privilegesRequired" => privilegesRequired,
        "scope" => scope,
        "userInteraction" => userInteractionV3,
        "vectorString" => cvss_v3_vector_string_with_default,
        "version" => cvss_builder.version.to_s,
      }
    end
  end

  def split_cvss_vector_string
    send(:"cvss_v#{cvss_key.match(/3|4/)}_vector_string_with_default").split("/")[1..].each_with_object({}) do |field, hash|
      key, value = field.split(":")
      hash[key] = value
      hash
    end
  end

  # Turn the CVSS vector string into a hash of field=>value pairs
  def cvss_fields
    @cvss_fields ||= split_cvss_vector_string
  end

  # Extact the code for a single metric of the CVSS vector string
  def extract_cvss_field(field_code)
    unless cvss_fields.key?(field_code)
      raise ArgumentError, "No field with code '#{field_code}' found in CVSS vector string #{cvss_vectorString}"
    end

    cvss_fields[field_code]
  end

  # Several of the CVSS metric fields have a common set of HIGH/LOW/NONE values
  HIGH_LOW_NONE = {
    "H" => "HIGH",
    "L" => "LOW",
    "N" => "NONE",
  }.freeze

  def attackComplexity
    HIGH_LOW_NONE[extract_cvss_field("AC")]
  end

  def confidentialityImpact
    HIGH_LOW_NONE[extract_cvss_field("C")]
  end

  def vulnConfidentialityImpact
    HIGH_LOW_NONE[extract_cvss_field("VC")]
  end

  def subConfidentialityImpact
    HIGH_LOW_NONE[extract_cvss_field("SC")]
  end

  def integrityImpact
    HIGH_LOW_NONE[extract_cvss_field("I")]
  end

  def vulnIntegrityImpact
    HIGH_LOW_NONE[extract_cvss_field("VI")]
  end

  def subIntegrityImpact
    HIGH_LOW_NONE[extract_cvss_field("SI")]
  end

  def availabilityImpact
    HIGH_LOW_NONE[extract_cvss_field("A")]
  end

  def vulnAvailabilityImpact
    HIGH_LOW_NONE[extract_cvss_field("VA")]
  end

  def subAvailabilityImpact
    HIGH_LOW_NONE[extract_cvss_field("SA")]
  end

  def privilegesRequired
    HIGH_LOW_NONE[extract_cvss_field("PR")]
  end

  ATTACK_VECTORS_V3 = {
    "N" => "NETWORK",
    "A" => "ADJACENT_NETWORK",
    "L" => "LOCAL",
    "P" => "PHYSICAL",
  }.freeze

  def attackVectorV3
    ATTACK_VECTORS_V3[extract_cvss_field("AV")]
  end

  ATTACK_VECTORS_V4 = {
    "N" => "NETWORK",
    "A" => "ADJACENT",
    "L" => "LOCAL",
    "P" => "PHYSICAL",
  }.freeze

  def attackVectorV4
    ATTACK_VECTORS_V4[extract_cvss_field("AV")]
  end

  ATTACK_REQUIREMENTS = {
    "N" => "NONE",
    "P" => "PRESENT",
  }.freeze

  def attackRequirements
    ATTACK_REQUIREMENTS[extract_cvss_field("AT")]
  end

  USER_INTERACTIONS_V3 = {
    "N" => "NONE",
    "R" => "REQUIRED",
  }.freeze

  def userInteractionV3
    USER_INTERACTIONS_V3[extract_cvss_field("UI")]
  end

  USER_INTERACTIONS_V4 = {
    "N" => "NONE",
    "P" => "PASSIVE",
    "A" => "ACTIVE",
  }.freeze

  def userInteractionV4
    USER_INTERACTIONS_V4[extract_cvss_field("UI")]
  end

  SCOPES = {
    "U" => "UNCHANGED",
    "C" => "CHANGED",
  }.freeze

  def scope
    SCOPES[extract_cvss_field("S")]
  end

  def cvss_key
    if AdvisoryDB::Features.enabled?("advisory_db_cvss_v4")
      if cvss_vectorString.present?
        if cvss_vectorString.start_with?("CVSS:4.0")
          "cvssV4_0"
        elsif cvss_vectorString.start_with?("CVSS:3.1")
          "cvssV3_1"
        elsif cvss_vectorString.start_with?("CVSS:3.0")
          "cvssV3_0"
        end
      end
    elsif cvss_vectorString.present?
      if cvss_vectorString.start_with?("CVSS:3.1")
        "cvssV3_1"
      elsif cvss_vectorString.start_with?("CVSS:3.0")
        "cvssV3_0"
      end
    end
  end

  def metrics
    if cvss_key.nil?
      []
    else
      [
        {
          cvss_key => cvss,
        },
      ]
    end
  end
end
# rubocop:enable Naming/MethodName
