# typed: true
# frozen_string_literal: true

class TopicStarrer
  def initialize(user:, topics:, context:)
    @user = user
    @topics = topics
    @context = context
  end

  def self.star(user:, topics:, context:)
    new(user: user, topics: topics, context: context).star
  end

  def star
    valid_topics.each do |topic|
      user.star(topic, context: context)
    end
  end

  private

  attr_reader :user, :topics, :context

  def valid_topics
    Topic.where(name: topics)
  end
end
