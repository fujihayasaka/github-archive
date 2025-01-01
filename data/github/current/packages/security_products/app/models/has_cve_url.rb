# typed: true
# frozen_string_literal: true

# This module handles building external links for CVE references. It's meant to
# be the one place to control exactly what URL we visit for any given CVE. The
# module is meant to be included in a class whose instances respond to cve_id.
# Otherwise, a cve_id can be passed in.
module HasCVEUrl
  def cve_url(cve_id: self.cve_id)
    cve_id ? "https://nvd.nist.gov/vuln/detail/#{cve_id}" : nil
  end
end
