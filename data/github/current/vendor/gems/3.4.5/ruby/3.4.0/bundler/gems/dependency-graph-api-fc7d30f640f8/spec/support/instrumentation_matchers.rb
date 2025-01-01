%w(count histogram increment time time_dist).each do |method|
  RSpec::Matchers.define "have_instrumented_#{method}".to_sym do |event, *args|
    match do |actual|
      @calls = []
      allow(Instrument).to receive(method.to_sym).and_wrap_original do |m, *args, &block|
        if args[0] == event
          @calls << args
        end

        if %w(count histogram).include?(method)
          name, val, tags = args
          m.call(name, val, **tags, &block)
        else
          m.call(args, &block)
        end
      end

      actual.call

      # the `with` matcher handles splats/veradic arguments poorly
      if args.empty?
        expect(Instrument).to have_received(method.to_sym).with(event)
      else
        expect(Instrument).to have_received(method.to_sym).with(event, *args)
      end
    end

    def supports_block_expectations?
      true
    end

    failure_message do |actual|
      if @calls.empty?
        "expected block to instrument #{method} for '#{event}' event, but nothing was instrumented"
      else
        <<-eos.strip_heredoc
          expected block to instrument #{method} '#{event}' event with arguments:
            #{print_args(args)}
          but got args:
            #{print_calls(@calls)}
        eos
      end
    end
  end

  def print_calls(calls)
    calls.map.with_index do |args, i|
      "#{i+1}) #{print_args(args)}"
    end.join("\n")
  end

  def print_args(args)
    args.join(", ")
  end
end
