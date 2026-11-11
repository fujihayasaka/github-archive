# frozen_string_literal: true

class RenameTypoedIndex < ActiveRecord::Migration[6.0]
  def change
    rename_index(
      :update_job_transitions,
      "index_udpate_job_transitions_parent_sort",
      "index_update_job_transitions_parent_sort",
    )
  end
end
