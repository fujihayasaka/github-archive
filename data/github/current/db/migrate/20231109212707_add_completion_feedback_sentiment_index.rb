class AddCompletionFeedbackSentimentIndex < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    add_index :copilot_completion_feedback, :sentiment
  end
end
