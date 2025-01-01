module DependencyGraphAPI
  class CurrentRequest < ActiveSupport::CurrentAttributes
    attribute :request_id

    def request_id=(request_id)
      super
    end
  end
end
