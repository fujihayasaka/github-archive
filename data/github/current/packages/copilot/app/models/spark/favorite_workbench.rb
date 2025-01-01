# typed: strict
# frozen_string_literal: true

module Spark
  class FavoriteWorkbench < ApplicationRecord::Copilot
    self.table_name = "favorite_spark_workbenches"

    belongs_to :user, optional: false
    belongs_to :workbench, class_name: "Spark::Workbench", foreign_key: "spark_workbench_id", optional: false, inverse_of: :favorites

    scope :for_user, ->(user) { where(user:) }

    # This scope is used to get the favorites for a user, ordered by created_at in descending order
    # and includes the workbench association to avoid N+1 queries.
    # It is used in the API response for the user's favorite workbenches (Favorites tab)
    scope :with_workbenches_for_user, ->(user) { where(user:).order(created_at: :desc).includes(:workbench) }

    sig { params(user: User, workbench_id: Integer).returns(Spark::FavoriteWorkbench) }
    def self.create_favorite(user:, workbench_id:)
      with_write { find_or_create_by!(user:, spark_workbench_id: workbench_id) }
    end

    sig { params(user: User, workbench_id: Integer).void }
    def self.remove_favorite(user:, workbench_id:)
      favorite = find_by(user: user, spark_workbench_id: workbench_id)
      return unless favorite

      favorite.destroy
    end
  end
end
