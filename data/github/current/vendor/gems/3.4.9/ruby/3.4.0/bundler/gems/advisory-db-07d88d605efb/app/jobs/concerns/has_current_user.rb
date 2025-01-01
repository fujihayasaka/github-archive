# frozen_string_literal: true

module HasCurrentUser
  extend ActiveSupport::Concern

  included do
    attr_accessor :current_user_login

    around_perform do |job, block|
      PaperTrail.request(whodunnit: job.current_user_login, &block)
    end
  end

  def serialize
    super.tap do |job_data|
      job_data["current_user_login"] = PaperTrail.request.whodunnit
    end
  end

  def deserialize(job_data)
    super
    self.current_user_login = job_data["current_user_login"]
  end
end
