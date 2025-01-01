# typed: true
# frozen_string_literal: true

module Spam
  class Conditional
    attr_accessor :conditions, :message, :hard_flag,
                  :flag_this, :log_this, :queue_this

    def initialize(options)
      if options.is_a? String
        options = JSON.parse options
      end
      options = HashWithIndifferentAccess.new(options || {})
      @hard_flag  = !!options["hard_flag"]
      @message    = options["message"]
      parse_actions options["actions"]
      @conditions = parse_conditions options["conditions"]
    end

    def parse_actions(actions)
      @flag_this  = (actions =~ /flag/i)
      @log_this   = (actions =~ /log/i)
      @queue_this = (actions =~ /queue/i)
    end

    def parse_conditions(raw_conditions)
      Array(raw_conditions).collect do |raw_condition|
        Spam::Condition.new raw_condition
      end
    end

    def matches?(target)
      conditions.all? { |c| c.matches? target }
    end

    def gather_actions
      list = []
      list << "flag" if @flag_this
      list << "log" if @log_this
      list << "queue" if @queue_this
      list.join(" ")
    end

    def gather_conditions
      @conditions.collect do |condition|
        condition.dump_as_hash
      end
    end

    def dump_to_json
      {
        actions: gather_actions,
        hard_flag: hard_flag,
        message: message,
        conditions: gather_conditions,
      }.to_json
    end
  end # class  Conditional
end   # module Spam
