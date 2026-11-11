# frozen_string_literal: true

class RelaxSecurityAdvisoryUniqueness < ActiveRecord::Migration[6.0]
  def up
    remove_index(
      :security_advisories,
      name: "index_security_advisories_on_ghsa_id",
    )
  end

  def down
    add_index(
      :security_advisories, :ghsa_id,
      unique: true,
      name: "index_security_advisories_on_ghsa_id",
    )
  end
end
