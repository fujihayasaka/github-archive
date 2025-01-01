# typed: true
# frozen_string_literal: true

module Api::Serializer::VulnerabilitiesDependency

  def cwe_hash(cwe, options = {})
    return unless cwe

    cwe.attributes.symbolize_keys
  end

  def vulnerabilities_hash(data, options = {})
    vulnerabilities = data.fetch(:vulnerabilities, [])
    vulnerabilities.map do |vulnerability|
      vulnerability_hash(vulnerability, options)
    end
  end

  def vulnerability_hash(vulnerability, options = {})
    return unless vulnerability

    hash = vulnerability.attributes.slice(*Vulnerability.attributes_for_enterprise)

    Vulnerability.associations_for_enterprise.each do |association|
      hash[association.to_sym] = vulnerability.public_send(association).map do |model|
        klass = Vulnerability.reflections[association].klass
        model.attributes.slice(*klass.attributes_for_enterprise)
      end
    end

    # Be warned, this is a hack to address the following issues:
    #   https://github.com/github/team-advisory-database/issues/4551
    #   https://github.com/github/team-advisory-database/issues/4750
    # This is a temporary fix until we can address the root cause of the issue
    # I chose not to do this in SQL because requirements isn't in any indexes and I want to have a light touch,
    # a little extra CPU seems OK.
    # Logic for rejecting long requirements can be removed once GHES 3.12 is deprecated.
    # Logic for rejecting long affects can be removed once GHES 3.14 is deprecated.
    if hash[:vulnerable_version_ranges].present?
      anything_rejected = T.let(false, T::Boolean)
      hash[:vulnerable_version_ranges] = hash[:vulnerable_version_ranges].reject do |vuln_range|
        reject_this_element = vuln_range["requirements"]&.length > 75 || vuln_range["affects"]&.length > 100
        anything_rejected ||= reject_this_element
        reject_this_element
      end

      if anything_rejected
        hash["description"] = (hash["description"] || "") + "\n" + "This advisory had affected versions omitted due to length. You can see the full advisory for this GHSA on GitHub's Advisory Database at #{vulnerability.permalink}"
      end
    end

    hash.symbolize_keys
  end
end
