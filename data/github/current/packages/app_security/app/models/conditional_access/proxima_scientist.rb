# typed: true
# frozen_string_literal: true

module ConditionalAccess
  class ProximaScientist
    def initialize(experiment_name)
      @experiment_name = experiment_name
      @use_block = nil
      @try_block = nil
      @compare_block = nil
      @run_if_block = nil
      @clean_block = nil
      @context_block = nil
    end

    def self.run(experiment_name, **kwargs)
      scientist = new(experiment_name)
      scientist.context(**kwargs) if kwargs.any?
      yield scientist
      scientist.run
    end

    def use(&block)
      @use_block = block
    end

    def try(&block)
      @try_block = block
    end

    def compare(&block)
      @compare_block = block
    end

    def run_if(&block)
      @run_if_block = block
    end

    def clean(&block)
      @clean_block = block
    end

    def context(**kwargs, &block)
      @context_block = block
      @context_kwargs = kwargs
    end

    def run
      # Call the context block if defined
      @context_block.call(@context_kwargs) if @context_block

      raise "Use block is not defined" unless @use_block
      raise "Try block is not defined" unless @try_block
      raise "Compare block is not defined" unless @compare_block

      # Always run the control block
      control_result = @use_block.call

      # Conditionally do science
      do_science(control_result)

      # Always return the control result
      control_result
    end

    private

    def do_science(control_result)
      candidate_result = nil
      if @run_if_block.nil? || @run_if_block.call
        begin
          candidate_result = @try_block.call
        rescue => e # rubocop:todo Lint/RescueException
          GitHub.logger.info(
            "Mismatch in authzd cap experiment",
            "code.function" => "do_science#try_block",
            "authzd.cap.experiment_name" => @experiment_name,
            "authzd.cap.error" => e.message,
          )
        end
      end

      # Only compare if the candidate block ran successfully
      @compare_block.call(control_result, candidate_result) if candidate_result
    rescue => e # rubocop:disable Lint/RescueException
      GitHub.logger.info(
        "Mismatch in authzd cap experiment",
        "code.function" => "do_science",
        "authzd.cap.experiment_name" => @experiment_name,
        "authzd.cap.error" => e.message,
      )
    end
  end
end
