# typed: true
class AddIndexOnClassroomAssignmentsForClassroomId < ActiveRecord::Migration[7.1]
  def change
    add_index :classroom_assignments, :classroom_classroom_id
  end
end
