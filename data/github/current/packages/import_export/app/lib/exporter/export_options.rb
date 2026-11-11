# typed: strict
# frozen_string_literal: true

module Exporter
  # Options for batch export serialization
  class ExportOptions < T::Struct
    const :exclude_git_data, T::Boolean, default: false
    const :org_metadata_only, T::Boolean, default: false
  end
end
