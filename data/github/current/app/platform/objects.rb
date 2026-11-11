# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    def self.async_find_record_by_id(model_name, id)
      Loaders::ActiveRecord.load(model_name, id.to_i).then do |object|
        # it's possible to construct the ID of an issue and attempt to pretend
        # it's an issue, even if it's actually a PR. Let's not do that.
        if model_name.to_s == "Issue" && object.try(:pull_request_id).present?
          object.async_pull_request
        else
          object
        end
      end
    end
  end
end
