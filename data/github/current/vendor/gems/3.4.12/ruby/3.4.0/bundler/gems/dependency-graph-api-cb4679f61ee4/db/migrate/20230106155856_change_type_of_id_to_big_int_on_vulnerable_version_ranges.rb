class ChangeTypeOfIdToBigIntOnVulnerableVersionRanges < ActiveRecord::Migration[6.0]
  def up
    change_table :dg_vulnerable_version_ranges do |t|
      t.change :id, :unsigned_bigint, auto_increment: true
    end
  end

  def down
    change_table :dg_vulnerable_version_ranges do |t|
      t.change :id, :int, auto_increment: true
    end
  end
end
