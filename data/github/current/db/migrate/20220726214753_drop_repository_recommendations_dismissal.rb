# typed: true
class DropRepositoryRecommendationsDismissal < ActiveRecord::Migration[7.1]
  def change
    drop_table :repository_recommendation_dismissals
  end
end
