# typed: true
#frozen_string_literal: true

require "advisory_db_toolkit"

module AdvisoryDB
  class SecurityAdvisorySerializer
    def initialize(advisory, form)
      @advisory = advisory
      @form = form
    end

    def create_advisory_file_content
      return @improve_advisory_content if defined?(@improve_advisory_content)

      osv_data = GitHub::OSV.ghsa_to_osv(@form.updated_advisory)
      @improve_advisory_content = JSON.pretty_generate(osv_data)
    end
  end
end
