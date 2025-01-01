class CheckpointsController < ApplicationController
  # POST /checkpoints
  # GET /checkpoints/:id
  def checkpoint
    @checkpoint = Checkpoint.with_name(params[:id]).first_or_create!(last_checkpointed_id: 0)
    render json: { value: @checkpoint.get }
  end

  # PUT /checkpoints/:id
  def set_checkpoint
    unless checkpoint_value_valid?
      render plain: "Checkpoint value #{params[:value].inspect} is invalid", status: :unprocessable_entity and return
    end

    @checkpoint = Checkpoint.with_name(params[:id]).first_or_create!(last_checkpointed_id: 0)
    @checkpoint.set!(params[:value])

    render json: { value: @checkpoint.get }
  end


  def checkpoint_value_valid?
    return false if params[:value].blank?

    begin
      !!Integer(params[:value])
    rescue ArgumentError
      false
    end
  end
end
