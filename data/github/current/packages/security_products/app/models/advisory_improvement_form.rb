# typed: true
# frozen_string_literal: true

class AdvisoryImprovementForm
  include AdvisoryDB::CvssScore

  attr_reader :justification, :updated_advisory, :current_user

  def initialize(params, advisory, current_user = nil)
    @justification = params.delete(:justification)
    @params = params
    @advisory = advisory
    @current_user = current_user

    # Create a duplicate of the advisory to add the new vulnerable version ranges, references and CWEs to.
    # The original advisory reference passed in should not be mutated.
    # The duplicate loses the association collection records that were present in the original.
    @updated_advisory = @advisory.dup

    # `updated_at` is required by the OSV transformer
    @updated_advisory.updated_at = @advisory.updated_at

    # ActiveModel::Dirty think all fields have changed, so
    # we need to reset that information so there are no changes.
    @updated_advisory.clear_changes_information
    # Update existing advisory params to check for changes and use the .changed? function
    # Vulnerable version ranges, references and CWEs will be compared separately.
    # Having called dup, there is no id associated with the object, so
    # operations such as direct assignment of association collection on the
    # object will not persist to the database.
    @updated_advisory.attributes = improve_advisory_params.except(:cwe_ids, :affected_products, :references)
    # Severity can be optional and skip validation in the model only if it is nil, not empty string.
    @updated_advisory.severity = nil if @updated_advisory.severity == ""

    # Update new advisory's CWEs
    @updated_advisory.cwes = CWE.where(cwe_id: improve_advisory_params[:cwe_ids]).to_a

    # Update new advisory's vulnerable version ranges
    @updated_advisory.vulnerable_version_ranges = parse_vvrs

    # Update new advisory's vulnerability references
    @updated_advisory.vulnerability_references = parse_references
  end

  def valid?
    return false if justification.blank?

    updated_advisory.valid? && valid_vvrs? && valid_references?
  end

  def changed_human_attributes
    return @changed_human_attributes if defined?(@changed_human_attributes)

    changed = @updated_advisory.changed.map { |attr| Vulnerability.human_attribute_name(attr) }
    changed << "Affected products" unless @advisory.has_same_vulnerable_version_ranges?(@updated_advisory)
    changed << "CWEs" unless @advisory.has_same_cwes?(@updated_advisory)
    changed << "References" unless @advisory.has_same_vulnerability_references?(@updated_advisory)
    @changed_human_attributes = changed
  end

  def changed?
    changed_human_attributes.any?
  end

  # Check validity of each vulnerable version range and add them to the updated_advisory
  def valid_vvrs?
    @updated_advisory.vulnerable_version_ranges.all?(&:valid?)
  end

  # Check validity of each reference and add them to the updated_advisory
  def valid_references?
    @updated_advisory.vulnerability_references.all?(&:valid?)
  end

  def parse_vvrs
    @params[:vulnerable_version_ranges].to_h&.map do |_index, range|
      vulnerable_version_range = VulnerableVersionRange.new(range.except(:ecosystem_other))
      # Certain fields are optional in community contribution form,
      # but not on the model itself.
      if range[:affects].blank?
        vulnerable_version_range.skip_affects_validation = true
      end
      if range[:requirements].blank?
        vulnerable_version_range.skip_requirements_validation = true
      end
      vulnerable_version_range
    end
  end

  def parse_references
    @params[:vulnerability_references].to_s.split(/\R/).map do |url|
      VulnerabilityReference.new(url: url.strip)
    end
  end

  def improve_advisory_params
    return @improve_advisory_params if defined?(@improve_advisory_params)

    {
      affected_products: parse_affected_products,
      cvss_v3: parse_cvss_v3,
      cvss_v4: parse_cvss_v4,
      cwe_ids: parse_cwe_ids,
      description: @params[:description],
      ghsa_id: @advisory.ghsa_id,
      references: parse_references.map { |reference| reference.url },
      severity: parse_severity,
      source_code_location: @params[:source_code_location],
      summary: @params[:summary]
    }
  end

  private

  def parse_affected_products
    @params[:vulnerable_version_ranges].to_h.map do |_index, vulnerable_version_range|
      ecosystem = vulnerable_version_range[:ecosystem]
      if ecosystem == "other"
        ecosystem = vulnerable_version_range[:ecosystem_other]
      end

      {
        package_ecosystem: ecosystem,
        package_name: vulnerable_version_range[:affects],
        vulnerable_version_range: vulnerable_version_range[:requirements],
        first_patched_version: vulnerable_version_range[:fixed_in],
      }
    end
  end

  def parse_cvss_v3
    if @params[:severity] == "cvss_v3"
      @params[:cvss_v3]
    else
      nil
    end
  end

  def parse_cvss_v4
    if @params[:severity] == "cvss_v4"
      @params[:cvss_v4]
    else
      nil
    end
  end

  def parse_cwe_ids
    CWE.where(id: @params[:cwes]).pluck(:cwe_id)
  end

  def parse_severity
    if @params[:severity] == "cvss_v4"
      severity_from_cvss(@params[:cvss_v4])
    elsif @params[:severity] == "cvss_v3"
      severity_from_cvss(@params[:cvss_v3])
    else
      @params[:severity]
    end
  end
end
