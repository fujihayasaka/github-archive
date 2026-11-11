# frozen_string_literal: true

require "throttler"
require "redis"

module Throttlers
  def self.pull_request
    @pull_request ||= Throttler.build("gh:pr")
  end
end

ActiveSupport::Notifications.subscribe("throttler.leader.taken") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  throttler = event.payload.fetch(:throttler)
  node_id = event.payload.fetch(:node_id)

  Rails.logger.debug("throttler.leader.taken: #{throttler}:#{node_id}")
  MetricsClient.increment("github_throttle.leader.taken",
                          tags: {
                            throttler: throttler,
                            node_id: node_id,
                          })
end

ActiveSupport::Notifications.subscribe("throttler.leader.renewed") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  throttler = event.payload.fetch(:throttler)
  node_id = event.payload.fetch(:node_id)

  Rails.logger.debug("throttler.leader.renewed: #{throttler}:#{node_id}")
  MetricsClient.increment("github_throttle.leader.renewed",
                          tags: {
                            throttler: throttler,
                            node_id: node_id,
                          })
end

ActiveSupport::Notifications.subscribe("throttler.leader.ack") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  throttler = event.payload.fetch(:throttler)
  node_id = event.payload.fetch(:node_id)
  leader_id = event.payload.fetch(:leader_id)

  Rails.logger.debug("throttler.leader.ack: #{throttler}:#{leader_id}")
  MetricsClient.increment("github_throttle.leader.ack",
                          tags: {
                            throttler: throttler,
                            node_id: node_id,
                            leader: leader_id,
                          })
end

ActiveSupport::Notifications.subscribe("throttler.print_ticket") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  throttler = event.payload.fetch(:throttler)
  key = event.payload.fetch(:key)
  ticket = event.payload.fetch(:ticket)

  Rails.logger.debug("throttler.ticket.printed: #{ticket}")
  MetricsClient.increment("github_throttle.ticket.printed",
                          tags: {
                            key: key,
                            throttler: throttler,
                          })
end

ActiveSupport::Notifications.subscribe("throttler.take_ticket") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  throttler = event.payload.fetch(:throttler)
  key = event.payload[:key]
  ticket = event.payload[:ticket]
  timeout = event.payload[:timeout]

  MetricsClient.timing("github_throttle.ticket.taken",
                       event.duration,
                       tags: {
                         timeout: timeout,
                         key: key,
                         throttler: throttler,
                       })

  if ticket
    Rails.logger.debug("throttle.ticket.taken: #{ticket}")
    age = Time.now.in_time_zone - ticket.to_f
    MetricsClient.timing("github_throttle.ticket.age",
                         age,
                         tags: {
                           timeout: timeout,
                           key: key,
                           throttler: throttler,
                         })
  end
end
