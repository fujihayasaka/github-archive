# frozen_string_literal: true

class FixCommit < ApplicationRecord
  belongs_to :vulnerability, touch: true

  def hydro_payload
    return nil if withdrawn_at?

    {
      commit_url: commit_url,
    }
  end
end
