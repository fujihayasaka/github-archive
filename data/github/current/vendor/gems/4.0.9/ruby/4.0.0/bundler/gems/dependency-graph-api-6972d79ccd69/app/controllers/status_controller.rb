class StatusController < ApplicationController
  def show
    # Verify the database connection is active
    begin
      ActiveRecord::Base.connection.verify!
    rescue => e
      render json: { status: "ERROR", message: "Database connection failed: #{e.message}" }, status: :service_unavailable
      return
    end

    render json: { status: "OK", time: Time.now.to_i }
  end

  def boom
    raise "boom"
  end

  def not_found
    render status: 404
  end
end
