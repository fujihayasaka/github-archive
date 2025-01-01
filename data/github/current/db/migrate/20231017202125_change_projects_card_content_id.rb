class ChangeProjectsCardContentId < ActiveRecord::Migration[7.2]
  def up
    change_table :project_cards, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :project_id, :bigint, unsigned: true
      t.change :column_id, :bigint, unsigned: true
      t.change :content_id, :bigint, unsigned: true
      t.change :creator_id , :bigint, unsigned: true
    end

    change_table :archived_project_cards, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :project_id, :bigint, unsigned: true
      t.change :column_id, :bigint, unsigned: true
      t.change :content_id, :bigint, unsigned: true
      t.change :creator_id , :bigint, unsigned: true
    end
  end

  def down
    change_table :project_cards, bulk: true do |t|
      t.change :id, :int
      t.change :project_id, :int
      t.change :column_id, :int
      t.change :content_id, :int
      t.change :creator_id, :int
    end

    change_table :archived_project_cards, bulk: true do |t|
      t.change :id, :int
      t.change :project_id, :int
      t.change :column_id, :int
      t.change :content_id, :int
      t.change :creator_id, :int
    end
  end
end
