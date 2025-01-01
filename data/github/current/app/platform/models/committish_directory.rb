# typed: true
# frozen_string_literal: true
class Platform::Models::CommittishDirectory < Platform::Models::CommittishObject
  def initialize(*)
    super

    if file_path.end_with?("/")
      # don't include the file path in this message, which is secret information
      raise Platform::Errors::Internal, "file_path must not end with \"/\""
    end
  end

  def type_name
    "CommittishDirectory"
  end

  def uri_type
    "tree"
  end
end
