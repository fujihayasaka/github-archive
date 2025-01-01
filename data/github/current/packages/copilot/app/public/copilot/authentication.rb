# typed: strict
# frozen_string_literal: true

module Copilot
  class Authentication
    extend T::Helpers

    sig { returns(String) }
    attr_reader :editor_details

    sig { returns(String) }
    attr_reader :ip_address

    sig { returns(Time) }
    attr_reader :timestamp

    sig { returns(Integer) }
    attr_reader :user_id

    sig do
      params(
        editor_details: String,
        ip_address: String,
        timestamp: Time,
        user_id: Integer,
      ).void
    end
    def initialize(editor_details:, ip_address:, timestamp:, user_id:)
      @editor_details = T.let(editor_details, String)
      @ip_address     = T.let(ip_address, String)
      @timestamp      = T.let(timestamp, Time)
      @user_id        = T.let(user_id, Integer)
    end

    sig { params(copilot_user: Copilot::User).returns(T.nilable(Copilot::Authentication)) }
    def self.latest_for_user(copilot_user)
      latest_for_user_id(copilot_user.id)
    end

    sig { params(user_id: Integer).returns(T.nilable(Copilot::Authentication)) }
    def self.latest_for_user_id(user_id)
      details = Copilot.redis.hgetall("last_authenticated:#{user_id}")

      unless details.empty?
        # if it's not empty, it's gonna be in this shape
        # {"editor_details"=>"vscode/1.92.0/", "ip_address"=>"1.1.1.1", "timestamp"=>"2021-06-01T00:00:00Z", "user_id"=>"1"}
        #
        new(
          editor_details: details["editor_details"].to_s,
          ip_address: details["ip_address"].to_s,
          # timestamp needs to be parsed in UTC
          timestamp: Time.parse(details["timestamp"].to_s).utc,
          user_id: user_id,
        )
      end
    end

    sig { params(user_ids: T::Array[Integer]).returns(T::Array[Copilot::Authentication]) }
    def self.latest_for_user_ids(user_ids)
      GitHub.logger.info("Loading latest authentications for user ids")
      Copilot.redis.pipelined do |pipeline|
        user_ids.map do |user_id|
          pipeline.hgetall("last_authenticated:#{user_id}")
        end
      end.map do |details|
        next if details.empty?

        new(
          editor_details: details["editor_details"].to_s,
          ip_address: details["ip_address"].to_s,
          # timestamp needs to be parsed in UTC
          timestamp: Time.parse(details["timestamp"].to_s).utc,
          user_id: details["user_id"].to_i,
        )
      end.compact
    end

    sig { params(copilot_organization: Copilot::Organization).returns(T::Array[Copilot::Authentication]) }
    def self.for_organization(copilot_organization)
      ## this loads up the auth detail for all users in the organization
      ## it does not look at whether they are CFB users or not - the assumption is that the activity service
      ## that writes to redis is only writing for CFB users
      organization = copilot_organization.organization_object
      latest_for_user_ids(organization.member_ids)
    end
  end
end
