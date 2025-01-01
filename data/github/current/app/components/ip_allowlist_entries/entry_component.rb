# typed: true
# frozen_string_literal: true

# Used to render a single IP allow list entry.
class IpAllowlistEntries::EntryComponent < ApplicationComponent
  with_collection_parameter :entry

  attr_reader :entry, :owner, :override_disabled

  def initialize(entry:, owner:, override_disabled: false)
    @entry = entry
    @owner = owner
    @override_disabled = override_disabled
  end

  def entry_description
    if owner == entry.owner
      entry.name
    else
      "Managed by the #{entry.owner_name_and_type}"
    end
  end
end
