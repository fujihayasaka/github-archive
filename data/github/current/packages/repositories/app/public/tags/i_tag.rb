# typed: strict
# frozen_string_literal: true

module Tags
  # [ref_name, target_oid, peeled_oid]
  ITag = T.type_alias do
    [String, String, String]
  end
end
