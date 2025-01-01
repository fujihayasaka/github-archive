# frozen_string_literal: true

# This json config file is taken from dotcom data: https://github.com/github/github/blob/master/config/cwe-data.json
# it is copied into this repo directly from that dotcom link
CWE_CONFIG_DATA = "config/cwe-data.json"

GitHub::Telemetry::Logs.logger.info("Loading CWE seed data")

def load_cwe_config_data
  cwe_json = File.read(CWE_CONFIG_DATA)
  JSON.parse(cwe_json)
end

cwes = load_cwe_config_data

GitHub::Telemetry::Logs.logger.info("#{cwes.count} CWEs in #{CWE_CONFIG_DATA}")

cwes.each_pair do |cwe_numeric_id, cwe_data|
  cwe_id = "CWE-#{cwe_numeric_id}"

  GitHub::Telemetry::Logs.logger.debug { "Creating CWE #{cwe_id}" }

  CWE.upsert({
    cwe_id: cwe_id,
    name: cwe_data["name"],
  })
end
