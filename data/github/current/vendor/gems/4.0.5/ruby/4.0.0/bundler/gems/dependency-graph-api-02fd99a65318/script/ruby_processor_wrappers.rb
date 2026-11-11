def handle_common_processor_errors(&block)
  if Rails.env.development?
    require_relative "dev/ruby_processor_wrappers"
    # included by the require_relative above, only when we're in development
    handle_development_processor_errors block
  else
    block.call
  end
end
