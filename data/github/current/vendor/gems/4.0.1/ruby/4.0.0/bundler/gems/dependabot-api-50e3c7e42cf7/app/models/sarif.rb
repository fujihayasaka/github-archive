# frozen_string_literal: true

class Sarif
  def initialize(file)
    @contents = if file.is_a?(String)
                  JSON.parse(file)
                else
                  file
                end
  end

  def dependency_declaration_location
    {
      file_path: package_json_path,
      start_line: start_line,
      end_line: end_line,
      start_column: start_column,
      end_column: end_column,
    }
  end

  def affected_file_paths
    locations =
      code_flows.
      first.
      fetch("threadFlows").
      first.
      fetch("locations")

    locations.map do |loc|
      loc.dig("location", "physicalLocation", "artifactLocation", "uri")
    end
  end

  def level
    value = result.fetch("level")

    # accepted values are "failure", "warning" and "notice"
    if value == "error"
      "failure"
    else
      "warning"
    end
  end

  def message
    result.fetch("message").fetch("text")
  end

  private

  attr_reader :contents

  def package_json_path
    package_json_location.
      fetch("artifactLocation").
      fetch("uri")
  end

  def start_line
    package_json_region.fetch("startLine")
  end

  def end_line
    package_json_region.fetch("endLine")
  end

  def start_column
    package_json_region.fetch("startColumn")
  end

  def end_column
    package_json_region.fetch("endColumn")
  end

  def package_json_region
    package_json_location.fetch("region")
  end

  def package_json_location
    result.
      fetch("locations").
      first.
      fetch("physicalLocation")
  end

  def code_flows
    result.fetch("codeFlows")
  end

  def result
    contents.
      fetch("runs").
      first.
      fetch("results").
      first
  end
end
