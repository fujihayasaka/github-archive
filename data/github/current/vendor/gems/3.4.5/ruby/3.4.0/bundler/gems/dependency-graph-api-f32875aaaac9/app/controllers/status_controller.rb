class StatusController < ApplicationController
  def show
    render json: { status: "OK", time: Time.now.to_i }
  end

  def boom
    raise "boom"
  end

  def not_found
    render status: 404
  end
end
