# typed: false
# frozen_string_literal: true
module GitSigning::NPlusOne
  Error = Class.new(StandardError)

  # initialize these here to simplify #check method.
  @this_request = nil
  @calls_this_request = Set.new

  # Check if this exact call stack has already occured within this request.
  #
  # Returns nothing. Raises Error.
  def check!
    return unless request_id = GitHub.context[:request_id]

    callers = caller
    return unless api_or_controller_caller?(callers)

    if @this_request != request_id
      @this_request = request_id
      @calls_this_request.clear
    end

    raise Error unless @calls_this_request.add?(caller_hash(callers))
  end

  private

  API_PATH        = Rails.root.join("app/api").to_s
  CONTROLLER_PATH = Rails.root.join("app/controllers").to_s

  def api_or_controller_caller?(callers)
    callers.any? { |c| c.start_with?(API_PATH, CONTROLLER_PATH) }
  end

  # Hash of the call stack.
  #
  # Returns an Integer.
  def caller_hash(callers)
    # This is ~8% faster than `caller.hash` on my machine.
    MessagePack.dump(callers).hash
  end

  extend self
end
