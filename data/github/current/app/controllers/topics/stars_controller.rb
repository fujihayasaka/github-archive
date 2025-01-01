# typed: true
# frozen_string_literal: true

module Topics
  class StarsController < ApplicationController

    # needs investigation for protected organization access
    skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction
    before_action :authorization_required, except: [:create, :destroy]
    before_action :login_required
    before_action :load_topic

    def create
      current_user.star(topic)

      render json: { count: topic.stargazer_count }
    end

    def destroy
      current_user.unstar(topic)

      render json: { count: topic.stargazer_count }
    end

    private

    attr_reader :topic

    def load_topic
      @topic = Topic.find_by(name: params[:topic_name])
      if !@topic
        render json: { message: "Topic not found" }, status: :unprocessable_entity
      end
    end
  end
end
