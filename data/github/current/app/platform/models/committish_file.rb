# typed: true
# frozen_string_literal: true
class Platform::Models::CommittishFile < Platform::Models::CommittishObject
  def type_name
    "CommittishFile"
  end

  def uri_type
    "blob"
  end
end
