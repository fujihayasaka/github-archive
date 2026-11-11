# typed: false
# frozen_string_literal: true

module Api::App::RequestMethodHelper
  REQUEST_METHOD = "REQUEST_METHOD".freeze
  READ_METHODS = %w[GET HEAD OPTIONS]

  module ClassMethods
    def read_request?(env)
      return true if READ_METHODS.include? env[REQUEST_METHOD]

      case Api::App.route_pattern(env)
      when "/repositories/:repository_id/statuses/:sha"
        true
      else
        false
      end
    end

    def write_request?(env)
      !read_request?(env)
    end
  end

  module InstanceMethods
    def read_request?(env_hash = nil)
      env_hash ||= (self.try(:env) || {})
      self.class.read_request?(env_hash)
    end

    def write_request?(env_hash = nil)
      env_hash ||= (self.try(:env) || {})
      self.class.write_request?(env_hash)
    end
  end

  def self.included(receiver)
    receiver.extend         ClassMethods
    receiver.send :include, InstanceMethods
  end
end
